# Dictation availability and retry

The editor microphone uses the device speech-recognition service. The Android
manifest already declares RECORD_AUDIO and the RecognitionService visibility
query. The plugin requests microphone permission only after Start dictation;
it does not save an audio recording. The service may process audio online.

The connected test phone reported no available RecognitionService and denied
microphone access. Those conditions prevent dictation independently of the note
text-insertion logic. The owner chose to install or enable Google speech
recognition. Provider installation and system voice-service changes are user
actions; the app does not silently install another provider or grant permission.

When Android explicitly reports recognizerNotAvailable, the editor now explains
that a speech-recognition service needs to be installed or enabled. Previously
that exception displayed only a microphone-permission suggestion. Internal
platform messages and exception details are never shown. Failed initialization
ends the attempt without listening or inserting text, and the same adapter can
retry after service setup. Existing cancellation and late-result guards remain.

To verify on the device: enable the Google app/speech provider, select a supported
recognition language, allow its microphone access if needed, then start dictation
inside Atomic Test and allow Atomic Test's microphone permission. Speak a short
test sentence and check partial replacement, final insertion, Stop, and unchanged
surrounding text. Do not claim physical speech acceptance from mocked tests.

Primary setup reference: [speech_to_text Android troubleshooting](https://github.com/csdcorp/speech_to_text/blob/main/speech_to_text/README.md#not-working-on-a-particular-android-device).
