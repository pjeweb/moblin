from .suites import browser_widget
from .suites import chat
from .suites import colors
from .suites import dji_camera
from .suites import gimbal
from .suites import http_proxy
from .suites import ingests
from .suites import macros
from .suites import mic
from .suites import mixer
from .suites import music
from .suites import record
from .suites import remote_control_scene_config
from .suites import scenes
from .suites import settings
from .suites import stream
from .suites import talkback
from .suites import tally
from .suites import web_remote_control
from .utils.runner import create_parser
from .utils.runner import run


def create_suites(moblin, args):
    if args.mixer_channels is not None or args.mixer_mic_delay:
        return mixer.tests(moblin, args.mixer_channels, args.mixer_mic_delay)
    return [
        talkback.tests(moblin),
        ingests.tests(moblin),
        record.tests(moblin),
        mic.tests(moblin),
        scenes.tests(moblin),
        remote_control_scene_config.tests(moblin),
        colors.tests(moblin),
        settings.tests(moblin),
        stream.tests(moblin),
        tally.tests(moblin),
        browser_widget.tests(moblin),
        chat.tests(moblin),
        dji_camera.tests(moblin),
        gimbal.tests(moblin),
        http_proxy.tests(moblin),
        macros.tests(moblin),
        music.tests(moblin),
        web_remote_control.tests(moblin),
    ]


def required_executables(args) -> tuple[str, ...] | None:
    if args.mixer_channels is not None:
        return ("ffmpeg", "ffprobe", "mediamtx")
    if args.mixer_mic_delay:
        return ("ffmpeg", "ffprobe")
    return None


def main():
    parser = create_parser("Run tests.")
    parser.add_argument(
        "--mixer-channels", type=int, choices=(1, 2), help="Run MixerTones with this channel count."
    )
    parser.add_argument("--mixer-mic-delay", action="store_true", help="Run the acoustic mixer A/V test.")
    run("test", parser, create_suites, required_executables)


main()
