#ifndef AudioMixerAtomic_h
#define AudioMixerAtomic_h

#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>

_Static_assert(__atomic_always_lock_free(sizeof(intptr_t), 0), "Audio mixer atomics must be lock-free");

typedef struct {
    _Atomic(intptr_t) value;
} AudioMixerAtomicStorage;

static inline AudioMixerAtomicStorage *_Nonnull makeAudioMixerAtomic(intptr_t value) {
    AudioMixerAtomicStorage *storage = malloc(sizeof(*storage));
    if (storage == NULL) {
        abort();
    }
    atomic_init(&storage->value, value);
    return storage;
}

static inline intptr_t exchangeAudioMixerAtomic(AudioMixerAtomicStorage *_Nonnull storage, intptr_t value) {
    return atomic_exchange_explicit(&storage->value, value, memory_order_acq_rel);
}

static inline void storeAudioMixerAtomic(AudioMixerAtomicStorage *_Nonnull storage, intptr_t value) {
    atomic_store_explicit(&storage->value, value, memory_order_release);
}

static inline intptr_t loadAudioMixerAtomic(AudioMixerAtomicStorage *_Nonnull storage) {
    return atomic_load_explicit(&storage->value, memory_order_acquire);
}

#endif
