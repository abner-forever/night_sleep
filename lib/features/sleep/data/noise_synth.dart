/// Synthesis of the eight sleep sounds.
///
/// **Why synthesise instead of shipping recordings.** The prototype does exactly
/// this — `App.tsx` builds each sound from `AudioContext.createBuffer` plus
/// white noise and a `BiquadFilter` — so this is the faithful port rather than a
/// substitute for one. It also means the app carries no third-party audio: no
/// attribution to track, no licence to check on every build, and no asset
/// pipeline. The alternative, bundling recordings, would need per-file licence
/// verification, and "free" ambient libraries usually require attribution.
///
/// Everything here is deterministic: the same [NoiseKind] always yields the same
/// bytes, so a test can assert on the waveform rather than on "it ran".
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// The eight sounds, keyed to match `kNoiseOptions` in the noise sheet.
enum NoiseKind {
  white('white'),
  brown('brown'),
  pink('pink'),
  rain('rain'),
  ocean('ocean'),
  fire('fire'),
  forest('forest'),
  fan('fan');

  const NoiseKind(this.id);

  final String id;

  static NoiseKind? fromId(String id) {
    for (final kind in NoiseKind.values) {
      if (kind.id == id) return kind;
    }
    return null;
  }
}

/// Sample rate for every generated loop.
///
/// 22.05 kHz is plenty for noise-based ambience — the content is broadband but
/// nothing here is musical — and it halves the memory and decode cost of 44.1.
const int kNoiseSampleRate = 22050;

/// Loop length. A whole number of seconds keeps the slow modulations (waves,
/// fan rotation) periodic across the seam.
const int kNoiseLoopSeconds = 20;

/// Peak the loop is normalised to before encoding. Leaves a little headroom so
/// the player's volume control has somewhere to go above unity.
const double _kPeak = 0.86;

/// Length of the tail-into-head crossfade that hides the loop seam.
const double _kSeamCrossfadeSeconds = 0.06;

/// Builds a loop of [kind] as 16-bit mono PCM WAV bytes.
///
/// The result is ready to hand to an audio player as-is; no further processing
/// is needed, and the caller should cache it because generating a 20-second loop
/// costs a few milliseconds and allocates ~880 KB.
Uint8List buildNoiseWav(NoiseKind kind, {int? seed}) {
  final samples = buildNoiseLoop(kind, seed: seed);
  return encodeWav(samples, sampleRate: kNoiseSampleRate);
}

/// The raw normalised samples behind [buildNoiseWav], for tests and for callers
/// that want to post-process.
///
/// Values are in `[-1, 1]`, DC-free, peaked at [_kPeak], and already seam-blended
/// so the loop can restart without a click.
Float64List buildNoiseLoop(NoiseKind kind, {int? seed}) {
  const length = kNoiseSampleRate * kNoiseLoopSeconds;
  final fade = (_kSeamCrossfadeSeconds * kNoiseSampleRate).round();

  // Generators run `fade` samples long. Those extra samples are the material the
  // seam is built from: the loop's first `fade` samples are a crossfade between
  // its own head and the continuation that would have followed the last sample.
  // Fading the loop's *own* tail into its head, which is the obvious thing to
  // do, does not work — the head would then start from a sample whose natural
  // predecessor is `length - fade`, not `length - 1`, so the step the fade was
  // meant to remove is still there.
  final total = length + fade;

  // Seeded per kind so the eight sounds differ from each other but each one is
  // reproducible run to run — a waveform that changed between launches would be
  // impossible to test and would make the loop seam unpredictable.
  final random = _Rng(seed ?? (0x5EED + kind.index * 7919));

  final samples = switch (kind) {
    NoiseKind.white => _white(random, total),
    NoiseKind.brown => _brown(random, total),
    NoiseKind.pink => _pink(random, total),
    NoiseKind.rain => _rain(random, total),
    NoiseKind.ocean => _ocean(random, total),
    NoiseKind.fire => _fire(random, total),
    NoiseKind.forest => _forest(random, total),
    NoiseKind.fan => _fan(random, total),
  };

  _removeDc(samples);
  _foldSeam(samples, loopLength: length, fade: fade);

  // Truncate first, then normalise: blending changes the peak, so normalising
  // before it would leave the finished loop at some other level.
  final loop = Float64List.sublistView(samples, 0, length);
  _normalise(loop, _kPeak);
  return loop;
}

// ── Generators ──────────────────────────────────────────────────────────────

Float64List _white(_Rng random, int length) {
  final out = Float64List(length);
  for (var i = 0; i < length; i++) {
    out[i] = random.nextSigned();
  }
  return out;
}

/// Brown (red) noise: white noise integrated by a leaky accumulator.
///
/// The leak matters — a pure integrator wanders off into inaudible sub-bass and
/// never comes back, so a little of the previous sample is bled off each step.
Float64List _brown(_Rng random, int length) {
  final out = Float64List(length);
  var last = 0.0;
  for (var i = 0; i < length; i++) {
    last = (last + 0.02 * random.nextSigned()) / 1.02;
    out[i] = last;
  }
  return out;
}

/// Pink noise: white noise shaped by −3 dB/octave.
///
/// Paul Kellet's economy filter — seven one-pole sections whose sum approximates
/// the pink slope closely enough to hear as "even" rather than "bright".
Float64List _pink(_Rng random, int length) {
  final out = Float64List(length);
  var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0;
  for (var i = 0; i < length; i++) {
    final w = random.nextSigned();
    b0 = 0.99886 * b0 + w * 0.0555179;
    b1 = 0.99332 * b1 + w * 0.0750759;
    b2 = 0.96900 * b2 + w * 0.1538520;
    b3 = 0.86650 * b3 + w * 0.3104856;
    b4 = 0.55000 * b4 + w * 0.5329522;
    b5 = -0.7616 * b5 - w * 0.0168980;
    out[i] = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362;
    b6 = w * 0.115926;
  }
  return out;
}

/// Rain: high-passed noise for the steady wash, plus individual droplets.
///
/// Droplets are what separate rain from plain hiss — each is a very short
/// decaying ping at a random pitch, which is how a drop landing on a surface
/// actually sounds.
Float64List _rain(_Rng random, int length) {
  final out = _highPassed(_white(random, length), 0.93);
  _addEvents(
    out,
    random: random,
    // ~45 droplets a second.
    density: 45.0,
    minGain: 0.10,
    maxGain: 0.42,
    minDecayMs: 3,
    maxDecayMs: 14,
  );
  return out;
}

/// Ocean: brown noise under a slow swell, with foam hiss on the crest.
Float64List _ocean(_Rng random, int length) {
  final surf = _brown(random, length);
  final hiss = _highPassed(_white(random, length), 0.86);
  final out = Float64List(length);

  // Four wave cycles across the loop, so the swell is periodic by construction.
  const waves = 4.0;
  for (var i = 0; i < length; i++) {
    final phase = i / length * waves * 2 * math.pi;
    // Unipolar swell: a wave is mostly trough with a rising crest.
    final swell = 0.42 + 0.58 * math.pow((math.sin(phase) + 1) / 2, 1.8);
    // Foam only where the wave is near its peak.
    final foam = math.pow((math.sin(phase) + 1) / 2, 6) * 0.35;
    out[i] = surf[i] * swell + hiss[i] * foam;
  }
  return out;
}

/// Campfire: a low rumble with irregular crackles on top.
Float64List _fire(_Rng random, int length) {
  final out = _brown(random, length);
  _addEvents(
    out,
    random: random,
    density: 16.0,
    minGain: 0.20,
    maxGain: 0.95,
    minDecayMs: 1,
    maxDecayMs: 7,
  );
  return out;
}

/// Forest: pink wind, plus occasional birdsong.
///
/// Birds are the reason this is synthesised with care rather than approximated:
/// a filtered-noise bed alone reads as "wind", and the design clearly means
/// "outside at night with wildlife". Each call is two or three short FM notes.
Float64List _forest(_Rng random, int length) {
  final out = _pink(random, length);
  final seconds = length / kNoiseSampleRate;

  // A call every ~2.5s on average, placed on a fixed grid so the pattern is
  // reproducible and several calls always fall inside the loop.
  final calls = (seconds / 2.5).floor();
  for (var c = 0; c < calls; c++) {
    final start =
        ((c + random.nextUnit() * 0.7) * seconds / calls * kNoiseSampleRate)
            .round()
            .clamp(0, length - 1);
    final notes = 2 + random.nextInt(2);
    var cursor = start;
    for (var n = 0; n < notes; n++) {
      final base = 2200 + random.nextUnit() * 1800;
      final noteSamples = (0.06 + random.nextUnit() * 0.07) * kNoiseSampleRate;
      for (var i = 0; i < noteSamples && cursor + i < length; i++) {
        final t = i / kNoiseSampleRate;
        final envelope = math.exp(-t * 34);
        // A falling pitch within each note is what makes it read as a bird
        // rather than a beep.
        final freq = base * (1.0 - 0.28 * (i / noteSamples));
        final vibrato = 1.0 + 0.05 * math.sin(2 * math.pi * 24 * t);
        out[cursor + i] +=
            0.34 * envelope * math.sin(2 * math.pi * freq * vibrato * t);
      }
      cursor += noteSamples.round();
    }
  }
  return out;
}

/// Fan: motor hum plus blade noise.
///
/// The hum is two harmonics, not one — a single sine reads as a test tone, while
/// a fundamental with a weaker octave above it reads as a motor.
Float64List _fan(_Rng random, int length) {
  final rumble = _brown(random, length);
  final blade = _highPassed(_white(random, length), 0.72);
  final out = Float64List(length);

  for (var i = 0; i < length; i++) {
    final t = i / kNoiseSampleRate;
    // 110 Hz and 220 Hz, both whole-cycle over the loop, so the hum is seamless.
    final hum = 0.16 * math.sin(2 * math.pi * 110 * t) +
        0.06 * math.sin(2 * math.pi * 220 * t);
    // A slow wobble keeps it from sounding like a machine on a bench.
    final wobble = 1.0 + 0.05 * math.sin(2 * math.pi * 0.4 * t);
    out[i] = rumble[i] * 0.55 * wobble + blade[i] * 0.30 + hum;
  }
  return out;
}

// ── Building blocks ─────────────────────────────────────────────────────────

/// One-pole high-pass. [amount] near 1 keeps only the top end (pure hiss),
/// lower values let more body through.
Float64List _highPassed(Float64List input, double amount) {
  final out = Float64List(input.length);
  var previousInput = 0.0;
  var previousOutput = 0.0;
  for (var i = 0; i < input.length; i++) {
    final value = input[i];
    previousOutput = amount * (previousOutput + value - previousInput);
    previousInput = value;
    out[i] = previousOutput;
  }
  return out;
}

/// Sprinkles short exponentially-decaying pings over [out], in place.
///
/// Used for raindrops and fire crackles: both are, physically, a broadband
/// transient that dies away in milliseconds.
void _addEvents(
  Float64List out, {
  required _Rng random,
  required double density,
  required double minGain,
  required double maxGain,
  required int minDecayMs,
  required int maxDecayMs,
}) {
  final seconds = out.length / kNoiseSampleRate;
  final count = (density * seconds).round();
  for (var e = 0; e < count; e++) {
    final at = (random.nextUnit() * out.length).floor();
    final gain = minGain + random.nextUnit() * (maxGain - minGain);
    final decayMs = minDecayMs + random.nextInt(maxDecayMs - minDecayMs + 1);
    final decaySamples =
        math.max(1, (decayMs / 1000 * kNoiseSampleRate).round());
    // A ring frequency in the audible upper-mid keeps the transient from
    // sounding like a click at the loop's DC level.
    final ring = 1400 + random.nextUnit() * 2600;
    for (var i = 0; i < decaySamples * 4 && at + i < out.length; i++) {
      final envelope = math.exp(-i / decaySamples * 4);
      if (envelope < 0.001) break;
      out[at + i] +=
          gain * envelope * math.sin(2 * math.pi * ring * i / kNoiseSampleRate);
    }
  }
}

/// Removes any constant offset, which would otherwise eat headroom and make the
/// loop pop when it restarts.
void _removeDc(Float64List samples) {
  var sum = 0.0;
  for (final value in samples) {
    sum += value;
  }
  final mean = sum / samples.length;
  if (mean.abs() < 1e-9) return;
  for (var i = 0; i < samples.length; i++) {
    samples[i] -= mean;
  }
}

void _normalise(Float64List samples, double peak) {
  var maxAbs = 0.0;
  for (final value in samples) {
    final magnitude = value.abs();
    if (magnitude > maxAbs) maxAbs = magnitude;
  }
  if (maxAbs == 0) return;
  final scale = peak / maxAbs;
  for (var i = 0; i < samples.length; i++) {
    samples[i] *= scale;
  }
}

/// Folds the [fade] samples past [loopLength] back over the loop's head.
///
/// Noise is continuous, but a loop is not: restarting mid-waveform steps the
/// signal, and that step is a click on every repetition. Blending the
/// continuation into the head makes the end of the loop flow into its start; the
/// cost is that the first [fade] samples are no longer "pure", which is
/// inaudible for ambience.
void _foldSeam(
  Float64List samples, {
  required int loopLength,
  required int fade,
}) {
  if (fade <= 0 || loopLength + fade > samples.length) return;
  for (var i = 0; i < fade; i++) {
    final t = i / fade;
    // Equal-power weighting holds the perceived loudness steady across the fade.
    samples[i] =
        samples[i] * math.sqrt(t) + samples[loopLength + i] * math.sqrt(1 - t);
  }
}

/// Wraps normalised samples in a 16-bit mono WAV container.
Uint8List encodeWav(Float64List samples, {required int sampleRate}) {
  const channels = 1;
  const bitsPerSample = 16;
  final dataBytes = samples.length * 2;

  final bytes = BytesBuilder();
  void ascii(String value) => bytes.add(value.codeUnits);
  void u32(int value) => bytes.add(
      Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little));
  void u16(int value) => bytes.add(
      Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little));

  ascii('RIFF');
  u32(36 + dataBytes);
  ascii('WAVE');
  ascii('fmt ');
  u32(16); // PCM chunk size
  u16(1); // PCM
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * channels * bitsPerSample ~/ 8); // byte rate
  u16(channels * bitsPerSample ~/ 8); // block align
  u16(bitsPerSample);
  ascii('data');
  u32(dataBytes);

  final pcm = Uint8List(dataBytes);
  final view = pcm.buffer.asByteData();
  for (var i = 0; i < samples.length; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    view.setInt16(i * 2, (clamped * 32767).round(), Endian.little);
  }
  bytes.add(pcm);

  return bytes.toBytes();
}

/// xorshift32: small, fast, and — unlike `Random(seed)` — its sequence is
/// specified by this file rather than by the SDK, so the generated waveforms
/// cannot shift under the tests when Dart changes its generator.
class _Rng {
  _Rng(int seed) : _state = seed & 0x7fffffff == 0 ? 1 : seed & 0x7fffffff;

  int _state;

  int nextInt(int maxExclusive) => (nextUnit() * maxExclusive).floor();

  /// Uniform in `[0, 1)`.
  double nextUnit() => _next() / 0x100000000;

  /// Uniform in `[-1, 1)`.
  double nextSigned() => nextUnit() * 2 - 1;

  int _next() {
    var x = _state;
    x ^= (x << 13) & 0x7fffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0x7fffffff;
    _state = x;
    return x;
  }
}
