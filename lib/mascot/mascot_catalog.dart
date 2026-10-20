/// App-pinned catalog v1. Original GIF bytes; no runtime discovery or URLs.
class MascotClip {
  const MascotClip(
      {required this.id,
      required this.sourcePath,
      required this.originalFilename,
      required this.slot,
      required this.bytes,
      required this.sha256,
      required this.width,
      required this.height,
      required this.frameCount,
      required this.encodedCycleDuration,
      this.bundledAssetPath});
  final String id, sourcePath, originalFilename, sha256;
  final int slot, bytes, width, height, frameCount;
  final Duration encodedCycleDuration;
  final String? bundledAssetPath;
}

class MascotDefinition {
  const MascotDefinition._(this.id, this.displayName, this.clips);
  final String id, displayName;
  final List<MascotClip> clips;
  int get encodedBytes => clips.fold(0, (sum, clip) => sum + clip.bytes);
}

abstract final class MascotCatalog {
  static const defaultId = '061-cubie';
  static MascotDefinition get defaultMascot => findById(defaultId)!;
  static MascotDefinition? findById(String id) {
    for (final mascot in all) {
      if (mascot.id == id) return mascot;
    }
    return null;
  }

  static const List<MascotDefinition> all = [
    MascotDefinition._('022-antimatter', 'Antimatter', [
      MascotClip(
          id: '022-antimatter-1-idle-blink',
          sourcePath:
              'assets/Atomic Notes Mascot/022 Antimatter/022-antimatter-1-idle-blink.gif',
          originalFilename: '022-antimatter-1-idle-blink.gif',
          slot: 1,
          bytes: 134084,
          sha256:
              'db094a3fbaf93bfdb959441ae90f6497e052a032b4b98bbeb40501ec78d82bd0',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '022-antimatter-2-invert-flip',
          sourcePath:
              'assets/Atomic Notes Mascot/022 Antimatter/022-antimatter-2-invert-flip.gif',
          originalFilename: '022-antimatter-2-invert-flip.gif',
          slot: 2,
          bytes: 230432,
          sha256:
              'bfe4fb8eca6e5597a0c6e1074b1a2a77712113585484620c116b3ecc10925876',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
      MascotClip(
          id: '022-antimatter-3-level-up-40-notes',
          sourcePath:
              'assets/Atomic Notes Mascot/022 Antimatter/022-antimatter-3-level-up-40-notes.gif',
          originalFilename: '022-antimatter-3-level-up-40-notes.gif',
          slot: 3,
          bytes: 193027,
          sha256:
              'd723f634fd3303cbe5ff982d1283eb735d455ee38a09c14752836131097fe58c',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
      MascotClip(
          id: '022-antimatter-4-antenna-charge',
          sourcePath:
              'assets/Atomic Notes Mascot/022 Antimatter/022-antimatter-4-antenna-charge.gif',
          originalFilename: '022-antimatter-4-antenna-charge.gif',
          slot: 4,
          bytes: 191339,
          sha256:
              'a9e5f90d0c1d98d4bfd66ec2ce7ac8899a594dacb2c93c33a9b878297a715a17',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
    ]),
    MascotDefinition._('038-ollie', 'Ollie', [
      MascotClip(
          id: '038-ollie-1-idle-blink',
          sourcePath:
              'assets/Atomic Notes Mascot/038 Ollie/038-ollie-1-idle-blink.gif',
          originalFilename: '038-ollie-1-idle-blink.gif',
          slot: 1,
          bytes: 108848,
          sha256:
              'da76417fe14b883c96560b27934e5cbec372854ea075b428689fe096b6f2a6be',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '038-ollie-2-night-watch',
          sourcePath:
              'assets/Atomic Notes Mascot/038 Ollie/038-ollie-2-night-watch.gif',
          originalFilename: '038-ollie-2-night-watch.gif',
          slot: 2,
          bytes: 126000,
          sha256:
              'e4b66e85ccf300848de514f0e253bd4e140741a5a14fb806168396ac382925f7',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
      MascotClip(
          id: '038-ollie-3-wing-flap-hop',
          sourcePath:
              'assets/Atomic Notes Mascot/038 Ollie/038-ollie-3-wing-flap-hop.gif',
          originalFilename: '038-ollie-3-wing-flap-hop.gif',
          slot: 3,
          bytes: 195681,
          sha256:
              '07413693b57036cfc05e544953139f49515ab41139bd5c6c6ffaebed3ab57c14',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '038-ollie-4-lock-the-vault',
          sourcePath:
              'assets/Atomic Notes Mascot/038 Ollie/038-ollie-4-lock-the-vault.gif',
          originalFilename: '038-ollie-4-lock-the-vault.gif',
          slot: 4,
          bytes: 169882,
          sha256:
              '0ac58cc3eb15e482dfb6bbc0a0860633ee936b677250a53ccb38b7bcf6ad2daf',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
    ]),
    MascotDefinition._('040-vaulty', 'Vaulty', [
      MascotClip(
          id: '040-vaulty-1-idle-blink',
          sourcePath:
              'assets/Atomic Notes Mascot/040 Vaulty/040-vaulty-1-idle-blink.gif',
          originalFilename: '040-vaulty-1-idle-blink.gif',
          slot: 1,
          bytes: 94172,
          sha256:
              '34bf5309010299617b1f2fde685f1de76d0284f0679c634723197da99d39ce95',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '040-vaulty-2-dial-spin-unlock',
          sourcePath:
              'assets/Atomic Notes Mascot/040 Vaulty/040-vaulty-2-dial-spin-unlock.gif',
          originalFilename: '040-vaulty-2-dial-spin-unlock.gif',
          slot: 2,
          bytes: 118195,
          sha256:
              'c75ca07a768bee7855a91e3ea98f4097cfb34a778a304e0f8a9f5c4a19b42cbe',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
      MascotClip(
          id: '040-vaulty-3-open-door-peek',
          sourcePath:
              'assets/Atomic Notes Mascot/040 Vaulty/040-vaulty-3-open-door-peek.gif',
          originalFilename: '040-vaulty-3-open-door-peek.gif',
          slot: 3,
          bytes: 162564,
          sha256:
              'ff01ef3851e909012d5e4531bcc322d95cff81b4ee3f9707c461df0308727247',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
      MascotClip(
          id: '040-vaulty-4-danger-zone-confirm',
          sourcePath:
              'assets/Atomic Notes Mascot/040 Vaulty/040-vaulty-4-danger-zone-confirm.gif',
          originalFilename: '040-vaulty-4-danger-zone-confirm.gif',
          slot: 4,
          bytes: 252494,
          sha256:
              'd3e40b32251a05c4fd25c6569318be21d87819de67e2e473a38965a1cd4098e6',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
    ]),
    MascotDefinition._('047-rocco', 'Rocco', [
      MascotClip(
          id: '047-rocco-1-idle-tail-swish',
          sourcePath:
              'assets/Atomic Notes Mascot/047 Rocco/047-rocco-1-idle-tail-swish.gif',
          originalFilename: '047-rocco-1-idle-tail-swish.gif',
          slot: 1,
          bytes: 153353,
          sha256:
              'e2a12841176747475f0e11f848b872d55266dc2bbf65ab523e6dc090d643e147',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '047-rocco-2-retry-5-15-45s',
          sourcePath:
              'assets/Atomic Notes Mascot/047 Rocco/047-rocco-2-retry-5-15-45s.gif',
          originalFilename: '047-rocco-2-retry-5-15-45s.gif',
          slot: 2,
          bytes: 315388,
          sha256:
              'ea94340c5a6aacc74e8e45de129ff8c62e2e01ee066f56ba62a4414968e12826',
          width: 480,
          height: 480,
          frameCount: 96,
          encodedCycleDuration: Duration(milliseconds: 4000)),
      MascotClip(
          id: '047-rocco-3-waddle',
          sourcePath:
              'assets/Atomic Notes Mascot/047 Rocco/047-rocco-3-waddle.gif',
          originalFilename: '047-rocco-3-waddle.gif',
          slot: 3,
          bytes: 197621,
          sha256:
              '34c5f4c1a381ee8887934fc1dd2c80aa2754ae327ae41daf5a1eb4cff608ad8d',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '047-rocco-4-retry-countdown',
          sourcePath:
              'assets/Atomic Notes Mascot/047 Rocco/047-rocco-4-retry-countdown.gif',
          originalFilename: '047-rocco-4-retry-countdown.gif',
          slot: 4,
          bytes: 132677,
          sha256:
              '557a1ccc1a770bf33a5df3019f64a3e3fa5a4fa808d155fe5c0f4a6559aec140',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
    ]),
    MascotDefinition._('049-sat', 'Sat', [
      MascotClip(
          id: '049-sat-1-float-glint',
          sourcePath:
              'assets/Atomic Notes Mascot/049 Sat/049-sat-1-float-glint.gif',
          originalFilename: '049-sat-1-float-glint.gif',
          slot: 1,
          bytes: 152190,
          sha256:
              'a6e1f23035b74ba2ffafd7d1bb37d9ea3f8c3720c718793b4f0da76bec488f16',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '049-sat-2-transmit-signal',
          sourcePath:
              'assets/Atomic Notes Mascot/049 Sat/049-sat-2-transmit-signal.gif',
          originalFilename: '049-sat-2-transmit-signal.gif',
          slot: 2,
          bytes: 171758,
          sha256:
              '56c0497cff059e7e7274899100d302be42463f09133f1e39d08ee84cfcb8e8b8',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '049-sat-3-orbit-the-cloud',
          sourcePath:
              'assets/Atomic Notes Mascot/049 Sat/049-sat-3-orbit-the-cloud.gif',
          originalFilename: '049-sat-3-orbit-the-cloud.gif',
          slot: 3,
          bytes: 197676,
          sha256:
              'd56dc318bdbd18334a5efe063b755b4bf2c3f9bdea8e11bebde732bc51b67d35',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
      MascotClip(
          id: '049-sat-4-count-cloud-notes',
          sourcePath:
              'assets/Atomic Notes Mascot/049 Sat/049-sat-4-count-cloud-notes.gif',
          originalFilename: '049-sat-4-count-cloud-notes.gif',
          slot: 4,
          bytes: 197762,
          sha256:
              '9a920a411f25d2221eec2e3297b8a2209173de79a630432c9730b1a61ac63181',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
    ]),
    MascotDefinition._('051-blink', 'Blink', [
      MascotClip(
          id: '051-blink-1-cursor-blink',
          sourcePath:
              'assets/Atomic Notes Mascot/051 Blink/051-blink-1-cursor-blink.gif',
          originalFilename: '051-blink-1-cursor-blink.gif',
          slot: 1,
          bytes: 43975,
          sha256:
              'ca2e7c93b7ae762939e38c5176ade3ffc61c64176af8f17012d6c91f50f399a9',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '051-blink-2-typing',
          sourcePath:
              'assets/Atomic Notes Mascot/051 Blink/051-blink-2-typing.gif',
          originalFilename: '051-blink-2-typing.gif',
          slot: 2,
          bytes: 132707,
          sha256:
              'b3aa77f1ecde562310b1422c88bb8a00ec8a122e7a052658d5451121cbd05be6',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
      MascotClip(
          id: '051-blink-3-thinking-loader',
          sourcePath:
              'assets/Atomic Notes Mascot/051 Blink/051-blink-3-thinking-loader.gif',
          originalFilename: '051-blink-3-thinking-loader.gif',
          slot: 3,
          bytes: 79965,
          sha256:
              '81657f5c992373e848c5ffcca2a3a3f7c7175d8ec154af6e5521b313894ba053',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '051-blink-4-happy-dance',
          sourcePath:
              'assets/Atomic Notes Mascot/051 Blink/051-blink-4-happy-dance.gif',
          originalFilename: '051-blink-4-happy-dance.gif',
          slot: 4,
          bytes: 124906,
          sha256:
              '6ec4d3f6dd35478e475e7f9bb1415f9ee2dd07ccb85c8b95f0da8a76d96e6ab2',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
    ]),
    MascotDefinition._('052-tilde', 'Tilde', [
      MascotClip(
          id: '052-tilde-1-wave-body',
          sourcePath:
              'assets/Atomic Notes Mascot/052 Tilde/052-tilde-1-wave-body.gif',
          originalFilename: '052-tilde-1-wave-body.gif',
          slot: 1,
          bytes: 94013,
          sha256:
              'cff445a74d0ef1f4dea8c3056e9dfaffa9dd482e33f3f90c1760c56d2ecabcd7',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '052-tilde-2-walk',
          sourcePath:
              'assets/Atomic Notes Mascot/052 Tilde/052-tilde-2-walk.gif',
          originalFilename: '052-tilde-2-walk.gif',
          slot: 2,
          bytes: 125177,
          sha256:
              '8247bc56d78ccfca4f96cdc6f213f18c2d5a22506c8337897beafe2d8234e046',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '052-tilde-3-type-home-prompt',
          sourcePath:
              'assets/Atomic Notes Mascot/052 Tilde/052-tilde-3-type-home-prompt.gif',
          originalFilename: '052-tilde-3-type-home-prompt.gif',
          slot: 3,
          bytes: 84985,
          sha256:
              'ecb4e7ab4212314657bfc05e23596b93c9a5a77e97066ef123381e80968a50ee',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
      MascotClip(
          id: '052-tilde-4-jump-squish',
          sourcePath:
              'assets/Atomic Notes Mascot/052 Tilde/052-tilde-4-jump-squish.gif',
          originalFilename: '052-tilde-4-jump-squish.gif',
          slot: 4,
          bytes: 105666,
          sha256:
              '4f2a1d44d7b158a8fe1b9e98cd0830d1f12ff74509650a25ca51ba7b73ff2f5b',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
    ]),
    MascotDefinition._('058-commit', 'Commit', [
      MascotClip(
          id: '058-commit-1-pulse',
          sourcePath:
              'assets/Atomic Notes Mascot/058 Commit/058-commit-1-pulse.gif',
          originalFilename: '058-commit-1-pulse.gif',
          slot: 1,
          bytes: 157582,
          sha256:
              '013865f0586d1abd4a3484508bd4a3fa75e40ddd633986149a5c5bd19f3de85d',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '058-commit-2-hop-to-next-commit',
          sourcePath:
              'assets/Atomic Notes Mascot/058 Commit/058-commit-2-hop-to-next-commit.gif',
          originalFilename: '058-commit-2-hop-to-next-commit.gif',
          slot: 2,
          bytes: 89639,
          sha256:
              'd811ae3683816ef85a6af6bd9b1a4f973c43192b5bd2e0151060a97bd3d048ad',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '058-commit-3-branch-and-merge',
          sourcePath:
              'assets/Atomic Notes Mascot/058 Commit/058-commit-3-branch-and-merge.gif',
          originalFilename: '058-commit-3-branch-and-merge.gif',
          slot: 3,
          bytes: 89490,
          sha256:
              '42373fcfe4992f388f5629325f258f671b0ecd9948949e3cdb0f6c68a98a0cff',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
      MascotClip(
          id: '058-commit-4-look-around-hop',
          sourcePath:
              'assets/Atomic Notes Mascot/058 Commit/058-commit-4-look-around-hop.gif',
          originalFilename: '058-commit-4-look-around-hop.gif',
          slot: 4,
          bytes: 61228,
          sha256:
              'a2fa491c7e23887722527ff62bf8da08f776b61aed8f6f0339ede6397fb8ab4f',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
    ]),
    MascotDefinition._('061-cubie', 'Cubie', [
      MascotClip(
          id: '061-cubie-1-bounce',
          sourcePath:
              'assets/Atomic Notes Mascot/061 Cubie/061-cubie-1-bounce.gif',
          originalFilename: '061-cubie-1-bounce.gif',
          slot: 1,
          bytes: 632455,
          sha256:
              '6fc98e9938079b450cdcd98da13ea9157dd170c5d7a9a7043897f10336a0f4f6',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000),
          bundledAssetPath:
              'assets/Atomic Notes Mascot/061 Cubie/061-cubie-1-bounce.gif'),
      MascotClip(
          id: '061-cubie-2-look-around',
          sourcePath:
              'assets/Atomic Notes Mascot/061 Cubie/061-cubie-2-look-around.gif',
          originalFilename: '061-cubie-2-look-around.gif',
          slot: 2,
          bytes: 303025,
          sha256:
              'da42010ed1d6d9a291e4c08f4e02f4fab90ca05bcad5c6db1c165683faf16d5b',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000),
          bundledAssetPath:
              'assets/Atomic Notes Mascot/061 Cubie/061-cubie-2-look-around.gif'),
      MascotClip(
          id: '061-cubie-3-spin-hop',
          sourcePath:
              'assets/Atomic Notes Mascot/061 Cubie/061-cubie-3-spin-hop.gif',
          originalFilename: '061-cubie-3-spin-hop.gif',
          slot: 3,
          bytes: 696613,
          sha256:
              '0eb7b93c2edbda8d6062c057601cf826fe5a02322deb5a3751a54dfa842ea128',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000),
          bundledAssetPath:
              'assets/Atomic Notes Mascot/061 Cubie/061-cubie-3-spin-hop.gif'),
      MascotClip(
          id: '061-cubie-4-write-the-lines',
          sourcePath:
              'assets/Atomic Notes Mascot/061 Cubie/061-cubie-4-write-the-lines.gif',
          originalFilename: '061-cubie-4-write-the-lines.gif',
          slot: 4,
          bytes: 575952,
          sha256:
              'c76d8cee141875674118c14ff10a06ff9b3b30bee521eef64759854d576637d3',
          width: 480,
          height: 480,
          frameCount: 96,
          encodedCycleDuration: Duration(milliseconds: 4000),
          bundledAssetPath:
              'assets/Atomic Notes Mascot/061 Cubie/061-cubie-4-write-the-lines.gif'),
    ]),
    MascotDefinition._('062-atomblock', 'Atomblock', [
      MascotClip(
          id: '062-atomblock-1-electron-orbit',
          sourcePath:
              'assets/Atomic Notes Mascot/062 Atomblock/062-atomblock-1-electron-orbit.gif',
          originalFilename: '062-atomblock-1-electron-orbit.gif',
          slot: 1,
          bytes: 720168,
          sha256:
              '41ecf61f58ad295091fbb11b8e985c618b14bd4fba3a13e5761cd7ced33bfdb2',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '062-atomblock-2-float-blink',
          sourcePath:
              'assets/Atomic Notes Mascot/062 Atomblock/062-atomblock-2-float-blink.gif',
          originalFilename: '062-atomblock-2-float-blink.gif',
          slot: 2,
          bytes: 1103719,
          sha256:
              '6e0596cd17706d1a1db7a7491478a6f8ba05fa50dfa22801422decf715311167',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
      MascotClip(
          id: '062-atomblock-3-charge-burst',
          sourcePath:
              'assets/Atomic Notes Mascot/062 Atomblock/062-atomblock-3-charge-burst.gif',
          originalFilename: '062-atomblock-3-charge-burst.gif',
          slot: 3,
          bytes: 1115675,
          sha256:
              'be39b4d1bfeed86ba3b47c512741b74bc26d84ef999dc8b00185c25ce9244365',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
      MascotClip(
          id: '062-atomblock-4-triple-orbit-atom',
          sourcePath:
              'assets/Atomic Notes Mascot/062 Atomblock/062-atomblock-4-triple-orbit-atom.gif',
          originalFilename: '062-atomblock-4-triple-orbit-atom.gif',
          slot: 4,
          bytes: 1567495,
          sha256:
              'b1339d659e1b74e6abb1faa692a44ef9408231d44d32f4d40686c433373b1ea6',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
    ]),
    MascotDefinition._('066-hoot', 'Hoot', [
      MascotClip(
          id: '066-hoot-1-blink-ear-twitch',
          sourcePath:
              'assets/Atomic Notes Mascot/066 Hoot/066-hoot-1-blink-ear-twitch.gif',
          originalFilename: '066-hoot-1-blink-ear-twitch.gif',
          slot: 1,
          bytes: 566154,
          sha256:
              'c4c007cb77aa954e0b4a371d14486a35b313e6c6d46103e44aa6e18d0a59e07b',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '066-hoot-2-wing-flap-hop',
          sourcePath:
              'assets/Atomic Notes Mascot/066 Hoot/066-hoot-2-wing-flap-hop.gif',
          originalFilename: '066-hoot-2-wing-flap-hop.gif',
          slot: 2,
          bytes: 828811,
          sha256:
              'bcab2fcc1c34f998268ed38eab95d02285e38b979eff46b95aa097c453528a14',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '066-hoot-3-head-turn',
          sourcePath:
              'assets/Atomic Notes Mascot/066 Hoot/066-hoot-3-head-turn.gif',
          originalFilename: '066-hoot-3-head-turn.gif',
          slot: 3,
          bytes: 574658,
          sha256:
              '4191d5fa343fc3cd061ea10ba6925f1c8fb94ef8d39c8ec3a1ee5913e7a3e3e8',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
      MascotClip(
          id: '066-hoot-4-sleepy-zzz',
          sourcePath:
              'assets/Atomic Notes Mascot/066 Hoot/066-hoot-4-sleepy-zzz.gif',
          originalFilename: '066-hoot-4-sleepy-zzz.gif',
          slot: 4,
          bytes: 1017378,
          sha256:
              'e04f74293e1bf535689b7ec54ae20f031daf084f95b032e6ab576da851c6d857',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
    ]),
    MascotDefinition._('073-lappy', 'Lappy', [
      MascotClip(
          id: '073-lappy-1-typing',
          sourcePath:
              'assets/Atomic Notes Mascot/073 Lappy/073-lappy-1-typing.gif',
          originalFilename: '073-lappy-1-typing.gif',
          slot: 1,
          bytes: 830996,
          sha256:
              '7f3bfeb5f61dfc967ef8dc272307755dc0363ba5684792006b68456843d4844d',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '073-lappy-2-close-lid-nap',
          sourcePath:
              'assets/Atomic Notes Mascot/073 Lappy/073-lappy-2-close-lid-nap.gif',
          originalFilename: '073-lappy-2-close-lid-nap.gif',
          slot: 2,
          bytes: 856360,
          sha256:
              'badb3f3d7bcfb543408fbc3e9876631435f6b2ef04f0d2b6eb96b612cc75f8bc',
          width: 480,
          height: 480,
          frameCount: 96,
          encodedCycleDuration: Duration(milliseconds: 4000)),
      MascotClip(
          id: '073-lappy-3-loading-bar',
          sourcePath:
              'assets/Atomic Notes Mascot/073 Lappy/073-lappy-3-loading-bar.gif',
          originalFilename: '073-lappy-3-loading-bar.gif',
          slot: 3,
          bytes: 341638,
          sha256:
              'de8b734023d8b59b1ac4958e02f44eaf15188ff5d3cce1a94a34da78f1c989a6',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
      MascotClip(
          id: '073-lappy-4-lid-wave-hello',
          sourcePath:
              'assets/Atomic Notes Mascot/073 Lappy/073-lappy-4-lid-wave-hello.gif',
          originalFilename: '073-lappy-4-lid-wave-hello.gif',
          slot: 4,
          bytes: 782640,
          sha256:
              '3a3a75527f5c4c88d9d058c71992540db680f56afdbb4bcba5f0290e54e9a67b',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
    ]),
    MascotDefinition._('076-pocket', 'Pocket', [
      MascotClip(
          id: '076-pocket-1-bounce-blink',
          sourcePath:
              'assets/Atomic Notes Mascot/076 Pocket/076-pocket-1-bounce-blink.gif',
          originalFilename: '076-pocket-1-bounce-blink.gif',
          slot: 1,
          bytes: 395661,
          sha256:
              '648e317c0759cbfc273e6b0d83f55dc4dbc3b2479b09a1ac110a4505011de73a',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '076-pocket-2-buzz-notification',
          sourcePath:
              'assets/Atomic Notes Mascot/076 Pocket/076-pocket-2-buzz-notification.gif',
          originalFilename: '076-pocket-2-buzz-notification.gif',
          slot: 2,
          bytes: 396158,
          sha256:
              '95a56e07e7faeb6e00fa4660a10f58bd0d9de6cae381e5e047dacd39ff92f6bc',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '076-pocket-3-spin-hop',
          sourcePath:
              'assets/Atomic Notes Mascot/076 Pocket/076-pocket-3-spin-hop.gif',
          originalFilename: '076-pocket-3-spin-hop.gif',
          slot: 3,
          bytes: 431027,
          sha256:
              'f5247b9a58f24b0762247193075bffbd6d5a566d998fcff522282788c8c640b4',
          width: 480,
          height: 480,
          frameCount: 48,
          encodedCycleDuration: Duration(milliseconds: 2000)),
      MascotClip(
          id: '076-pocket-4-save-notes-locally',
          sourcePath:
              'assets/Atomic Notes Mascot/076 Pocket/076-pocket-4-save-notes-locally.gif',
          originalFilename: '076-pocket-4-save-notes-locally.gif',
          slot: 4,
          bytes: 300238,
          sha256:
              'fd11b868625154bf724516649ded800c75110877f731e3056ef67f43bc7cdea7',
          width: 480,
          height: 480,
          frameCount: 72,
          encodedCycleDuration: Duration(milliseconds: 3000)),
    ]),
  ];
}
