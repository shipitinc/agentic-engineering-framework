/// End-to-end coverage for the upgrade merge engine (ADR 0004).
///
/// The fixtures build a throwaway *framework* repository (a minimal Mason brick
/// committed twice) and a throwaway *product* repository bootstrapped from the
/// first revision, then run the real upgrade against them. Nothing here touches
/// the network or any real repository, and the framework revision is resolved
/// from the sandbox framework checkout (ADR 0004 § 2), so these tests are
/// hermetic and do not depend on this checkout living at any absolute path.
library;

import 'dart:io';

import 'package:framework_cli/framework_cli.dart';
import 'package:test/test.dart';

const _brickYaml = '''
name: aef_upgrade_fixture
description: Minimal brick for upgrade engine tests
version: 1.0.0
environment:
  mason: ">=0.1.0 <0.2.0"
vars:
  frameworkRevision:
    type: string
    description: Framework revision under test
    default: TBD
    prompt: Framework revision
''';

/// Managed files shipped by the framework revision under test. `AGENTS.md` has
/// four lines so a test can edit one region locally and a different region
/// upstream, which is the case git can merge without a conflict.
const _baseFiles = <String, String>{
  'AGENTS.md': 'line one\nshared line\nline three\nline four\n',
  'docs/engineering/WORK_STATE.md': 'base work state\n',
};

/// The locally customized copy of `AGENTS.md` used by several tests.
const _customizedAgents =
    'product customized agents\nshared line\nline three\nline four\n';

class _Fixture {
  _Fixture({
    required this.root,
    required this.frameworkRepo,
    required this.productRepo,
    required this.revA,
    required this.revB,
  });

  final Directory root;
  final Directory frameworkRepo;
  final Directory productRepo;
  final String revA;
  final String revB;
}

/// Builds a framework repo with two revisions and a product repo bootstrapped
/// from [revA]. [incomingFiles] are the `__brick__` files at [revB];
/// [productFiles] are extra product-owned files added on top of the render.
_Fixture _createFixture({
  Map<String, String> incomingFiles = const {},
  Map<String, String> productFiles = const {},
  List<String> removedAtIncoming = const [],
  Map<String, String> productOverlays = const {},
}) {
  final root = Directory.systemTemp.createTempSync('aef_fixture_');
  final frameworkRepo = Directory('${root.path}/framework')..createSync();
  final productRepo = Directory('${root.path}/product')..createSync();
  final remote = Directory('${root.path}/remote')..createSync();

  _writeBrick(frameworkRepo, _baseFiles);
  _git(frameworkRepo, ['init', '-q', '-b', 'main', '.']);
  _configureIdentity(frameworkRepo);
  _git(frameworkRepo, ['add', '-A']);
  _git(frameworkRepo, ['commit', '-qm', 'framework revision A']);
  final revA = _gitOut(frameworkRepo, ['rev-parse', 'HEAD']);

  final nextBrick = <String, String>{..._baseFiles, ...incomingFiles};
  for (final removed in removedAtIncoming) {
    nextBrick.remove(removed);
  }
  // Guarantee revision B differs from revision A: without a real change git
  // records no second commit and both revisions would be the same SHA, which
  // would exercise the same-revision no-op instead of an upgrade.
  if (_sameContent(nextBrick, _baseFiles)) {
    nextBrick['CHANGELOG.md'] = 'revision B\n';
  }
  _writeBrick(frameworkRepo, nextBrick);
  _git(frameworkRepo, ['add', '-A']);
  _git(frameworkRepo, ['commit', '-qm', 'framework revision B']);
  final revB = _gitOut(frameworkRepo, ['rev-parse', 'HEAD']);

  // Product repository: revision A rendered, plus the product's own files and
  // its committed local customizations of managed artifacts — which is what a
  // real product looks like, and what the dirty-tree guard permits.
  _git(productRepo, ['init', '-q', '-b', 'main', '.']);
  _configureIdentity(productRepo);
  _git(productRepo, ['remote', 'add', 'origin', remote.path]);
  _renderInto(productRepo, _baseFiles);
  productFiles.forEach((path, content) => _writeFile(productRepo, path, content));

  // The manifest records the rendered hashes, so an overlaid artifact is
  // detectable as locally modified.
  _writeProductManifest(productRepo, revA, _baseFiles);
  productOverlays.forEach((path, content) {
    _writeFile(productRepo, path, content);
  });
  _git(productRepo, ['add', '-A']);
  _git(productRepo, ['commit', '-qm', 'product bootstrapped at revision A']);

  return _Fixture(
    root: root,
    frameworkRepo: frameworkRepo,
    productRepo: productRepo,
    revA: revA,
    revB: revB,
  );
}

bool _sameContent(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

void _writeBrick(Directory frameworkRepo, Map<String, String> files) {
  final templates = Directory('${frameworkRepo.path}/framework/templates');
  templates.createSync(recursive: true);
  File('${templates.path}/brick.yaml').writeAsStringSync(_brickYaml);
  final brick = Directory('${templates.path}/__brick__');
  if (brick.existsSync()) brick.deleteSync(recursive: true);
  brick.createSync(recursive: true);
  files.forEach((path, content) => _writeFile(brick, path, content));
}

/// Mirrors what a Mason render of the brick produces in a product repository.
void _renderInto(Directory target, Map<String, String> files) {
  files.forEach((path, content) => _writeFile(target, path, content));
}

void _writeFile(Directory root, String relativePath, String content) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

void _writeProductManifest(
  Directory productRepo,
  String revision,
  Map<String, String> managedFiles,
) {
  final artifacts = <ManagedArtifact>[];
  for (final path in managedFiles.keys) {
    final file = File('${productRepo.path}/$path');
    final hash = ContentHash.ofFile(file);
    artifacts.add(
      ManagedArtifact(path: path, sourceHash: hash, installHash: hash),
    );
  }
  FrameworkManifest(
    source: 'https://example.test/framework.git',
    revision: revision,
    version: '0.1.0',
    instantiatedAt: DateTime.utc(2026, 1, 1),
    artifacts: artifacts,
  ).write().let((yaml) {
    File('${productRepo.path}/framework-manifest.yaml').writeAsStringSync(yaml);
  });
}

void _configureIdentity(Directory repo) {
  _git(repo, ['config', 'user.email', 'fixture@example.test']);
  _git(repo, ['config', 'user.name', 'Upgrade Fixture']);
}

ProcessResult _git(Directory cwd, List<String> args) =>
    Process.runSync('git', args, workingDirectory: cwd.path);

String _gitOut(Directory cwd, List<String> args) {
  final result = _git(cwd, args);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

/// Runs the upgrade with the sandbox framework resolved as the render source.
Future<CommandResult> _runUpgrade(_Fixture fixture, {String? targetRevision}) {
  return runUpgradeCore(
    productRepo: fixture.productRepo,
    targetRevision: targetRevision ?? fixture.revB,
    frameworkRootOverride: fixture.frameworkRepo.path,
  );
}

String _fileAt(String repoPath, String revision, String path) {
  final result = Process.runSync('git', ['show', '$revision:$path'],
      workingDirectory: repoPath);
  if (result.exitCode != 0) {
    throw StateError('missing $path at $revision');
  }
  return result.stdout as String;
}

/// Contents of the delivered upgrade branch for [path].
String _fileOnBranch(_Fixture fixture, String branch, String path) =>
    _fileAt(fixture.productRepo.path, branch, path);

List<Directory> _scratchDirs() => Directory.systemTemp
    .listSync()
    .whereType<Directory>()
    .where((d) => d.path.split('/').last.startsWith('aef_upgrade_'))
    .toList();

void main() {
  test('clean merge delivers one review commit and preserves local edits',
      () async {
    final fixture = _createFixture(
      incomingFiles: {'docs/engineering/ROADMAP.md': 'upstream roadmap\n'},
      productFiles: {'apps/mobile/lib/main.dart': 'void main() {}\n'},
      // The product edited a managed file the framework did not touch.
      productOverlays: const {'AGENTS.md': _customizedAgents},
    );
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    final result = await _runUpgrade(fixture);

    expect(
      result.family,
      ResultFamily.upgradeReadyForReview,
      reason: 'upgrade result: ${result.message} ${result.blockers}',
    );
    expect(result.humanActionRequired, isFalse);

    final branch = 'framework/upgrade-${fixture.revA.substring(0, 12)}-'
        '${fixture.revB.substring(0, 12)}';

    // The branch exists in the product repository, as one commit on its history.
    final head = _gitOut(fixture.productRepo, ['rev-parse', 'HEAD']);
    final branchHead = _gitOut(fixture.productRepo, ['rev-parse', branch]);
    expect(branchHead, isNot(head));
    expect(
      _gitOut(fixture.productRepo, ['rev-list', '--count', '$head..$branchHead']),
      '1',
    );
    expect(
      _gitOut(fixture.productRepo, ['rev-parse', '$branchHead^']),
      head,
      reason: 'the upgrade must be parented on the product real HEAD',
    );

    // Upstream change applied, product edit preserved, product file untouched.
    expect(
      _fileOnBranch(fixture, branch, 'docs/engineering/ROADMAP.md'),
      'upstream roadmap\n',
    );
    expect(_fileOnBranch(fixture, branch, 'AGENTS.md'), _customizedAgents);
    expect(
      _fileOnBranch(fixture, branch, 'apps/mobile/lib/main.dart'),
      'void main() {}\n',
    );

    // The product working tree was never mutated.
    expect(_gitOut(fixture.productRepo, ['status', '--porcelain']), isEmpty);
    expect(
      File('${fixture.productRepo.path}/AGENTS.md').readAsStringSync(),
      _customizedAgents,
    );
  });

  test('merged framework change and local edit combine in one file', () async {
    final fixture = _createFixture(
      // Upstream changes the last line...
      incomingFiles: {
        'AGENTS.md': 'line one\nshared line\nline three\nupstream line\n',
      },
      // ...while the product changed the second: git merges both regions.
      productOverlays: const {
        'AGENTS.md': 'line one\nproduct line\nline three\nline four\n',
      },
    );
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    final result = await _runUpgrade(fixture);

    expect(result.family, ResultFamily.upgradeReadyForReview);
    final branch = 'framework/upgrade-${fixture.revA.substring(0, 12)}-'
        '${fixture.revB.substring(0, 12)}';
    final merged = _fileOnBranch(fixture, branch, 'AGENTS.md');
    expect(merged, contains('product line'));
    expect(merged, contains('upstream line'));
    expect(merged, isNot(contains('<<<<<<<')));
  });

  test('conflicting merge is reported, delivered with markers, and blocks',
      () async {
    final fixture = _createFixture(
      incomingFiles: const {
        'AGENTS.md': 'upstream agents\nshared line\nline three\nline four\n',
      },
      productOverlays: const {
        'AGENTS.md': 'product agents\nshared line\nline three\nline four\n',
      },
    );
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    final result = await _runUpgrade(fixture);

    expect(result.family, ResultFamily.upgradeConflict);
    expect(result.humanActionRequired, isTrue);
    expect(result.blockers.join(' '), contains('AGENTS.md'));

    final branch = 'framework/upgrade-${fixture.revA.substring(0, 12)}-'
        '${fixture.revB.substring(0, 12)}';
    final conflicted = _fileOnBranch(fixture, branch, 'AGENTS.md');
    expect(conflicted, contains('<<<<<<<'));
    expect(conflicted, contains('>>>>>>>'));
    // Paths git merged cleanly are still delivered.
    expect(_fileOnBranch(fixture, branch, 'docs/engineering/WORK_STATE.md'),
        'base work state\n');
  });

  test('upstream deletion of a locally modified artifact is a conflict',
      () async {
    final fixture = _createFixture(
      removedAtIncoming: ['docs/engineering/WORK_STATE.md'],
      productOverlays: {
        'docs/engineering/WORK_STATE.md': 'product own work state\n',
      },
    );
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    final result = await _runUpgrade(fixture);

    expect(result.family, ResultFamily.upgradeConflict);
    expect(
      result.blockers.join(' '),
      contains('docs/engineering/WORK_STATE.md'),
    );
  });

  test('unmodified artifact deleted upstream is deleted, not flagged',
      () async {
    final fixture = _createFixture(
      removedAtIncoming: ['docs/engineering/WORK_STATE.md'],
    );
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    final result = await _runUpgrade(fixture);

    expect(result.family, ResultFamily.upgradeReadyForReview);
    expect(result.message, contains('Deleted: 1'));
    final branch = 'framework/upgrade-${fixture.revA.substring(0, 12)}-'
        '${fixture.revB.substring(0, 12)}';
    final exists = _git(fixture.productRepo,
        ['cat-file', '-e', '$branch:docs/engineering/WORK_STATE.md']);
    expect(exists.exitCode, isNot(0));
  });

  test('delivered commit refreshes the manifest to the incoming revision',
      () async {
    final fixture = _createFixture(
      incomingFiles: const {'docs/engineering/ROADMAP.md': 'upstream roadmap\n'},
      productOverlays: const {'AGENTS.md': _customizedAgents},
    );
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    await _runUpgrade(fixture);
    final branch = 'framework/upgrade-${fixture.revA.substring(0, 12)}-'
        '${fixture.revB.substring(0, 12)}';

    final manifest = FrameworkManifest.parse(
      _fileOnBranch(fixture, branch, 'framework-manifest.yaml'),
    );
    expect(manifest.revision, fixture.revB);
    expect(manifest.upgradedAt, isNotNull);
    expect(manifest.instantiatedAt, DateTime.utc(2026, 1, 1));
    expect(manifest.managedPaths, contains('docs/engineering/ROADMAP.md'));

    // Locally customized artifact: source and install hashes must differ, so
    // the customization stays detectable after the upgrade.
    final customized =
        manifest.artifacts.firstWhere((a) => a.path == 'AGENTS.md');
    expect(customized.sourceHash, isNot(customized.installHash));

    // Untouched artifact stays identical on both sides.
    final untouched = manifest.artifacts
        .firstWhere((a) => a.path == 'docs/engineering/ROADMAP.md');
    expect(untouched.sourceHash, untouched.installHash);

    // The product file itself was never added to the manifest.
    expect(manifest.managedPaths, isNot(contains('apps/mobile/lib/main.dart')));
  });

  test('re-run is refused while the previous upgrade awaits review', () async {
    final fixture = _createFixture();
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    final first = await _runUpgrade(fixture);
    expect(first.family, isNot(ResultFamily.upgradeBlocked));

    final second = await _runUpgrade(fixture);
    expect(second.family, ResultFamily.upgradeBlocked);
    expect(second.blockers.join(' '), contains('already exists'));
  });

  test('upgrading to the pinned revision is a no-op', () async {
    final fixture = _createFixture();
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    final result = await runUpgradeCore(
      productRepo: fixture.productRepo,
      targetRevision: fixture.revA,
    );

    expect(result.family, ResultFamily.upgradeNoop);
  });

  test('scratch state is discarded on success and on failure', () async {
    final before = _scratchDirs().length;

    final success = _createFixture();
    addTearDown(() => success.root.deleteSync(recursive: true));
    await _runUpgrade(success);
    expect(_scratchDirs().length, before,
        reason: 'a successful upgrade must not leave scratch state');

    // Failure path: target revision that the framework source does not contain.
    final failure = _createFixture();
    addTearDown(() => failure.root.deleteSync(recursive: true));
    final result = await _runUpgrade(
      failure,
      targetRevision: '0000000000000000000000000000000000000000',
    );
    expect(result.family, ResultFamily.upgradeBlocked);
    expect(_scratchDirs().length, before,
        reason: 'a failed upgrade must not leave scratch state');
  });

  test('upgrade never writes into the product working tree', () async {
    final fixture = _createFixture(
      incomingFiles: {'docs/engineering/ROADMAP.md': 'upstream roadmap\n'},
    );
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    await _runUpgrade(fixture);

    expect(_gitOut(fixture.productRepo, ['status', '--porcelain']), isEmpty);
    final manifestOnDisk =
        File('${fixture.productRepo.path}/framework-manifest.yaml')
            .readAsStringSync();
    expect(
      FrameworkManifest.parse(manifestOnDisk).revision,
      fixture.revA,
      reason: 'the delivered branch carries the new pin, not the working tree',
    );
    // No stray patch file was left behind (which would break the next preflight).
    expect(
      fixture.productRepo
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.patch')),
      isEmpty,
    );
  });

  test('previous product revision stays reachable from the delivered commit',
      () async {
    final fixture = _createFixture(
      incomingFiles: {'docs/engineering/ROADMAP.md': 'upstream roadmap\n'},
    );
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    await _runUpgrade(fixture);
    final branch = 'framework/upgrade-${fixture.revA.substring(0, 12)}-'
        '${fixture.revB.substring(0, 12)}';

    // Merging the review branch needs no --allow-unrelated-histories, which
    // is only true if the product real history is an ancestor of it.
    final merged = _git(fixture.productRepo, [
      'merge-tree',
      '--write-tree',
      'HEAD',
      branch,
    ]);
    expect(merged.exitCode, 0);
    expect((merged.stdout as String).trim(), isNotEmpty);
  });
}

extension on String {
  void let(void Function(String) action) => action(this);
}