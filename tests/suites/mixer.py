import logging
from pathlib import Path
from statistics import median

from systest_moblin.ffmpeg import FfmpegServer
from systest_moblin.ffmpeg import ffmpeg_run
from systest_moblin.ffmpeg import ffprobe_audio
from systest_moblin.ffmpeg import measure_audio_band_levels

from ..utils.audio_video_sync import alert_media_files
from ..utils.config import RTMP_SERVER_PORT
from ..utils.config import srt_listener_url
from ..utils.config import srt_reader_url
from ..utils.generate_device_settings import FRONT_SCENE_SETTINGS
from ..utils.generate_device_settings import RECORD_STREAM_SETTINGS
from ..utils.generate_device_settings import CameraPosition
from ..utils.generate_device_settings import SceneName
from ..utils.generate_device_settings import mic_id
from ..utils.generate_device_settings import mics_settings
from ..utils.generate_device_settings import uuid
from ..utils.mediamtx import MediaMtx
from ..utils.moblin import Moblin
from ..utils.test_case import AUDIO_SAMPLES_PER_FRAME
from ..utils.test_case import TestCase
from ..utils.utils import FILES_DIR
from ..utils.utils import manual_volume_requirement
from .mic import TONE_WINDOW
from .mic import FfmpegToneTestStream
from .mic import MicDelay
from .mic import ToneMic
from .mic import settings_overrides

LOGGER = logging.getLogger(__name__)
LOWERED_GAIN_DB = -18


class MixerTones(TestCase):
    """Stream two mixed RTMP tones over SRT and verify source isolation, gain and channel count."""

    def __init__(self, moblin: Moblin, expected_channels: int):
        super().__init__(moblin)
        self._main = ToneMic(uuid(), "mixer-main", 1000, 48000, 1)
        self._secondary = ToneMic(uuid(), "mixer-secondary", 2500, 44100, 2)
        self._expected_channels = expected_channels

    def run(self):
        with MediaMtx() as server:
            mixed = self._capture(server, "mixed")
            muted = self._capture(server, "stream-muted", output="Recording")
            lowered = self._capture(server, "lowered", gain=LOWERED_GAIN_DB)
        self.assert_greater(mixed[0], -40, "Main tone baseline (dBFS).")
        self.assert_greater(mixed[1], -40, "Mixed tone baseline (dBFS).")
        self.assert_less(abs(muted[0] - mixed[0]), 3, "Main tone changed when the mixed tone was muted.")
        self.assert_less(abs(lowered[0] - mixed[0]), 3, "Main tone changed when the mixed gain was lowered.")
        self.assert_less(muted[1] - mixed[1], -30, "Stream mute did not remove the mixed tone.")
        self.assert_less(
            abs(lowered[1] - mixed[1] - LOWERED_GAIN_DB),
            4,
            "Mixed tone attenuation did not match the configured gain.",
        )

    def _capture(
        self,
        server: MediaMtx,
        stage: str,
        output: str = "Stream and recording",
        gain: int = 0,
    ) -> tuple[float, float]:
        mics = [self._main, self._secondary]
        self.moblin.import_settings(
            overrides={
                "debug": {"audioMixer": True, "logLevel": "Debug"},
                "streams": [
                    {
                        **RECORD_STREAM_SETTINGS,
                        "url": self.moblin.tester_srt_publish_url(stage),
                        "srt": {"adaptiveBitrateEnabled": False},
                    }
                ],
                "scenes": [
                    {
                        **FRONT_SCENE_SETTINGS,
                        "cameraPosition": CameraPosition.RTMP,
                        "rtmpCameraId": self._main.stream_id,
                    }
                ],
                "mics": {
                    "autoSwitch": False,
                    "all": [
                        {
                            "name": f"{self._secondary.stream_key} (RTMP)",
                            "inputUid": self._secondary.stream_id,
                            "mixed": True,
                            "output": output,
                            "gainDb": gain,
                        }
                    ],
                },
                "rtmpServer": {
                    "enabled": True,
                    "port": RTMP_SERVER_PORT,
                    "streams": [
                        {"id": mic.stream_id, "name": mic.stream_key, "streamKey": mic.stream_key}
                        for mic in mics
                    ],
                },
            }
        )
        self.moblin.wait_for_tcp_ports(RTMP_SERVER_PORT)
        main, secondary = [
            FfmpegToneTestStream(self.moblin.ingest_rtmp_url(mic.stream_key), mic) for mic in mics
        ]
        capture = FILES_DIR / f"{self.name}-{stage}.ts"
        with main, secondary:
            self.wait_for_ingest_stream_started(number_of_ingests=2)
            self.moblin.set_scene(SceneName.FRONT)
            names = {mic["id"]: mic["name"] for mic in self.moblin.get_mics()}
            main_name = names[mic_id(self._main.stream_id)]
            mixed_name = names[mic_id(self._secondary.stream_id)]
            self.moblin.set_mic(main_name)
            self.wait_until(lambda: self.moblin.get_mic() == f"{main_name} + {mixed_name}")
            try:
                self.moblin.go_live()
                server.wait_for_srt_stream(stage, 1_000_000)
                ffmpeg_run(
                    "-i",
                    srt_reader_url(stage),
                    "-t",
                    "5",
                    "-map",
                    "0:a:0",
                    "-c",
                    "copy",
                    str(capture),
                )
            finally:
                self.moblin.end()
        return self._measure(capture, stage)

    def _measure(self, capture: Path, stage: str) -> tuple[float, float]:
        audio = ffprobe_audio(capture)
        self.assert_equal(audio.sample_rate, 48000)
        self.assert_equal(audio.channels, self._expected_channels)
        self.assert_greater(len(audio.frames), 4 * audio.sample_rate / AUDIO_SAMPLES_PER_FRAME)
        self.assert_true(all(frame.channels == self._expected_channels for frame in audio.frames))
        main, secondary = (self._band_levels(capture, mic.frequency) for mic in (self._main, self._secondary))
        if stage == "mixed":
            self.assert_equal(len(main), len(secondary))
            both_present = sum(a > -40 and b > -40 for a, b in zip(main, secondary))
            self.assert_greater_equal(both_present, 0.8 * len(main), "Both tones must be present together.")
        levels = (median(main), median(secondary))
        LOGGER.info("%s: %d channels, main %.1f dBFS, mixed %.1f dBFS", stage, audio.channels, *levels)
        return levels

    def _band_levels(self, capture: Path, frequency: int) -> list[float]:
        filters = [f"bandpass=f={frequency}:width_type=h:w=50"] * 2
        windows = measure_audio_band_levels(capture, filters, TONE_WINDOW)
        self.assert_greater_equal(len(windows), 16, "Usable audio windows.")
        return [window.level for window in windows[2:-2]]


class MixerMicDelay(MicDelay):
    """Compare the built-in mic A/V offset with the mixer on and off at the app's default delay."""

    def __init__(self, moblin: Moblin):
        super().__init__(moblin)
        self._enabled = False

    def run(self):
        manual_volume_requirement(LOGGER)
        reference = self._measure_stream_offset()
        self._enabled = True
        mixed = self._measure_stream_offset()
        LOGGER.info(
            "SRT A/V offset at default delay: mixer off %+.0f ms, mixer on %+.0f ms",
            reference * 1000,
            mixed * 1000,
        )
        self.assert_less(abs(mixed - reference), 0.06, "SRT A/V offset changed at the default delay.")

    def _measure_stream_offset(self) -> float:
        self._import_settings(0)
        self.moblin.set_scene(SceneName.FRONT)
        stream_file = FILES_DIR / f"{self._file_name(0)}.ts"
        with FfmpegServer(url=srt_listener_url(), filename=stream_file):
            try:
                self.moblin.go_live()
                self.moblin.wait_for_bitrate(4_000_000, 6_000_000, None, 2_000_000)
                self._trigger_alerts()
            finally:
                self.moblin.end()
        return self._measure_offset(stream_file)

    def _import_settings(self, delay: float):
        mics = self.moblin.get_mics()
        self.assert_greater(len(mics), 0)
        self.moblin.import_settings(
            overrides={
                **settings_overrides(self.moblin),
                "debug": {"audioMixer": self._enabled, "logLevel": "Debug"},
                "mics": mics_settings(mics, delay),
            },
            files=alert_media_files(),
        )
        self.moblin.set_main_mic()

    def _file_name(self, delay: float) -> str:
        return f"{self.name}-mixer-{'on' if self._enabled else 'off'}"


def tests(moblin: Moblin, channels: int | None, mic_delay: bool) -> list[TestCase]:
    cases: list[TestCase] = []
    if channels is not None:
        cases.append(MixerTones(moblin, channels))
    if mic_delay:
        cases.append(MixerMicDelay(moblin))
    return cases
