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
/// from [revA]. [baseFiles] are the `__brick__` files at [revA];
/// [incomingFiles] are the `__brick__` files added or changed at [revB];
/// [productFiles] are extra product-owned files added on top of the render.
_Fixture _createFixture({
  Map<String, String> baseFiles = _baseFiles,
  Map<String, String> incomingFiles = const {},
  Map<String, String> productFiles = const {},
  List<String> removedAtIncoming = const [],
  Map<String, String> productOverlays = const {},
}) {
  final root = Directory.systemTemp.createTempSync('aef_fixture_');
  final frameworkRepo = Directory('${root.path}/framework')..createSync();
  final productRepo = Directory('${root.path}/product')..createSync();
  final remote = Directory('${root.path}/remote')..createSync();

  _writeBrick(frameworkRepo, baseFiles);
  _git(frameworkRepo, ['init', '-q', '-b', 'main', '.']);
  _configureIdentity(frameworkRepo);
  _git(frameworkRepo, ['add', '-A', '-f']);
  _git(frameworkRepo, ['commit', '-qm', 'framework revision A']);
  final revA = _gitOut(frameworkRepo, ['rev-parse', 'HEAD']);

  final nextBrick = <String, String>{...baseFiles, ...incomingFiles};
  for (final removed in removedAtIncoming) {
    nextBrick.remove(removed);
  }
  // Guarantee revision B differs from revision A: without a real change git
  // records no second commit and both revisions would be the same SHA, which
  // would exercise the same-revision no-op instead of an upgrade.
  if (_sameContent(nextBrick, baseFiles)) {
    nextBrick['CHANGELOG.md'] = 'revision B\n';
  }
  _writeBrick(frameworkRepo, nextBrick);
  _git(frameworkRepo, ['add', '-A', '-f']);
  _git(frameworkRepo, ['commit', '-qm', 'framework revision B']);
  final revB = _gitOut(frameworkRepo, ['rev-parse', 'HEAD']);

  // Product repository: revision A rendered, plus the product's own files and
  // its committed local customizations of managed artifacts — which is what a
  // real product looks like, and what the dirty-tree guard permits.
  _git(productRepo, ['init', '-q', '-b', 'main', '.']);
  _configureIdentity(productRepo);
  _git(productRepo, ['remote', 'add', 'origin', remote.path]);
  _renderInto(productRepo, baseFiles);
  productFiles.forEach(
    (path, content) => _writeFile(productRepo, path, content),
  );

  // The manifest records the rendered hashes, so an overlaid artifact is
  // detectable as locally modified.
  _writeProductManifest(productRepo, revA, baseFiles);
  productOverlays.forEach((path, content) {
    _writeFile(productRepo, path, content);
  });
  // `-f` for the same reason the engine stages its trees with it: a rendered
  // `.gitignore` that excludes a path the framework also renders must not cost
  // the product that artifact.
  _git(productRepo, ['add', '-A', '-f']);
  _git(productRepo, ['commit', '-qm', 'product bootstrapped at revision A']);

  return _Fixture(
    root: root,
    frameworkRepo: frameworkRepo,
    productRepo: productRepo,
    revA: revA,
    revB: revB,
  );
}

/// Files the brick stages *outside* `__brick__/`: the brick's own build inputs,
/// which a Mason render never emits into a product.
const _brickStagedFiles = <String, String>{
  'brick.yaml': _brickYaml,
  'manifest.template.yaml': 'artifacts: []\n',
  'product-repo/AGENTS.template.md': '# templated agents\n',
  'README.md': 'brick readme\n',
};

/// A product bootstrapped from the *brick directory* rather than from a render.
///
/// It carries byte-identical copies of the brick's build inputs, keeps the
/// brick's own `__brick__/` directory, and has a manifest that claims only those
/// copies. Because the copies are identical to what the base render emits, git's
/// rename detection pairs them with the base files and reports rename/rename
/// conflicts that no human ever caused. The engine must recognise the copies as
/// staging artifacts, keep them out of the merge, and report them.
_Fixture _createStagingFixture({
  Map<String, String> incomingFiles = const {},
  Map<String, String> productStagingOverrides = const {},
  Map<String, String> productOwnFiles = const {},
}) {
  final root = Directory.systemTemp.createTempSync('aef_staging_');
  final frameworkRepo = Directory('${root.path}/framework')..createSync();
  final productRepo = Directory('${root.path}/product')..createSync();
  final remote = Directory('${root.path}/remote')..createSync();

  final revAFiles = <String, String>{
    ..._baseFiles,
    'agents/implementer.md': 'implementer agent\n',
  };
  final revBFiles = <String, String>{
    ...revAFiles,
    ...incomingFiles,
    'agents/implementer.md': 'implementer agent v2\n',
  };

  void commitBrick(String message, Map<String, String> brickFiles) {
    _writeBrick(frameworkRepo, brickFiles);
    final templates = Directory('${frameworkRepo.path}/framework/templates');
    _brickStagedFiles.forEach(
      (path, content) => _writeFile(templates, path, content),
    );
    _git(frameworkRepo, ['add', '-A']);
    _git(frameworkRepo, ['commit', '-qm', message]);
  }

  _git(frameworkRepo, ['init', '-q', '-b', 'main', '.']);
  _configureIdentity(frameworkRepo);
  commitBrick('framework revision A', revAFiles);
  final revA = _gitOut(frameworkRepo, ['rev-parse', 'HEAD']);
  commitBrick('framework revision B', revBFiles);
  final revB = _gitOut(frameworkRepo, ['rev-parse', 'HEAD']);

  // The product is the brick directory copied verbatim, exactly what a bootstrap
  // that renders nothing leaves behind.
  _git(productRepo, ['init', '-q', '-b', 'main', '.']);
  _configureIdentity(productRepo);
  _git(productRepo, ['remote', 'add', 'origin', remote.path]);
  revAFiles.forEach(
    (path, content) => _writeFile(productRepo, '__brick__/$path', content),
  );
  final staged = {..._brickStagedFiles, ...productStagingOverrides};
  staged.forEach((path, content) => _writeFile(productRepo, path, content));
  productOwnFiles.forEach(
    (path, content) => _writeFile(productRepo, path, content),
  );
  _writeProductManifest(productRepo, revA, staged);
  _git(productRepo, ['add', '-A']);
  _git(productRepo, ['commit', '-qm', 'product bootstrapped from brick dir']);

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
  final result = Process.runSync('git', [
    'show',
    '$revision:$path',
  ], workingDirectory: repoPath);
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

/// Scratch directories that appeared since [before] was captured.
///
/// The system temp directory is shared, so counting `aef_upgrade_*` directories
/// cannot tell this run's leftovers from a concurrent run's or from a previously
/// interrupted one. Comparing against the set captured before the run makes the
/// assertion about state this run actually created.
List<Directory> _newScratchDirs(Set<String> before) =>
    _scratchDirs().where((d) => !before.contains(d.path)).toList();

Set<String> _scratchDirPaths() => {for (final dir in _scratchDirs()) dir.path};

/// Every test here drives real git and a real Mason render. A slow machine can
/// legitimately blow the default 30s per-test budget without anything being
/// wrong, and a gate that fails for that reason hides the regressions it exists
/// to catch, so the budget is generous by design.
const _e2eTimeout = Timeout(Duration(minutes: 2));

void main() {
  test(
    'clean merge delivers one review commit and preserves local edits',
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

      final branch =
          'framework/upgrade-${fixture.revA.substring(0, 12)}-'
          '${fixture.revB.substring(0, 12)}';

      // The branch exists in the product repository, as one commit on its history.
      final head = _gitOut(fixture.productRepo, ['rev-parse', 'HEAD']);
      final branchHead = _gitOut(fixture.productRepo, ['rev-parse', branch]);
      expect(branchHead, isNot(head));
      expect(
        _gitOut(fixture.productRepo, [
          'rev-list',
          '--count',
          '$head..$branchHead',
        ]),
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
    },
    timeout: _e2eTimeout,
  );

  test(
    'merged framework change and local edit combine in one file',
    () async {
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
      final branch =
          'framework/upgrade-${fixture.revA.substring(0, 12)}-'
          '${fixture.revB.substring(0, 12)}';
      final merged = _fileOnBranch(fixture, branch, 'AGENTS.md');
      expect(merged, contains('product line'));
      expect(merged, contains('upstream line'));
      expect(merged, isNot(contains('<<<<<<<')));
    },
    timeout: _e2eTimeout,
  );

  test(
    'conflicting merge is reported, delivered with markers, and blocks',
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

      final branch =
          'framework/upgrade-${fixture.revA.substring(0, 12)}-'
          '${fixture.revB.substring(0, 12)}';
      final conflicted = _fileOnBranch(fixture, branch, 'AGENTS.md');
      expect(conflicted, contains('<<<<<<<'));
      expect(conflicted, contains('>>>>>>>'));
      // Paths git merged cleanly are still delivered.
      expect(
        _fileOnBranch(fixture, branch, 'docs/engineering/WORK_STATE.md'),
        'base work state\n',
      );
    },
    timeout: _e2eTimeout,
  );

  test(
    'upstream deletion of a locally modified artifact is a conflict',
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
    },
    timeout: _e2eTimeout,
  );

  test(
    'unmodified artifact deleted upstream is deleted, not flagged',
    () async {
      final fixture = _createFixture(
        removedAtIncoming: ['docs/engineering/WORK_STATE.md'],
      );
      addTearDown(() => fixture.root.deleteSync(recursive: true));

      final result = await _runUpgrade(fixture);

      expect(result.family, ResultFamily.upgradeReadyForReview);
      expect(result.message, contains('Deleted: 1'));
      final branch =
          'framework/upgrade-${fixture.revA.substring(0, 12)}-'
          '${fixture.revB.substring(0, 12)}';
      final exists = _git(fixture.productRepo, [
        'cat-file',
        '-e',
        '$branch:docs/engineering/WORK_STATE.md',
      ]);
      expect(exists.exitCode, isNot(0));
    },
    timeout: _e2eTimeout,
  );

  test(
    'delivered commit refreshes the manifest to the incoming revision',
    () async {
      final fixture = _createFixture(
        incomingFiles: const {
          'docs/engineering/ROADMAP.md': 'upstream roadmap\n',
        },
        productOverlays: const {'AGENTS.md': _customizedAgents},
      );
      addTearDown(() => fixture.root.deleteSync(recursive: true));

      await _runUpgrade(fixture);
      final branch =
          'framework/upgrade-${fixture.revA.substring(0, 12)}-'
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
      final customized = manifest.artifacts.firstWhere(
        (a) => a.path == 'AGENTS.md',
      );
      expect(customized.sourceHash, isNot(customized.installHash));

      // Untouched artifact stays identical on both sides.
      final untouched = manifest.artifacts.firstWhere(
        (a) => a.path == 'docs/engineering/ROADMAP.md',
      );
      expect(untouched.sourceHash, untouched.installHash);

      // The product file itself was never added to the manifest.
      expect(
        manifest.managedPaths,
        isNot(contains('apps/mobile/lib/main.dart')),
      );
    },
    timeout: _e2eTimeout,
  );

  test(
    're-run is refused while the previous upgrade awaits review',
    () async {
      final fixture = _createFixture();
      addTearDown(() => fixture.root.deleteSync(recursive: true));

      final first = await _runUpgrade(fixture);
      expect(first.family, isNot(ResultFamily.upgradeBlocked));

      final second = await _runUpgrade(fixture);
      expect(second.family, ResultFamily.upgradeBlocked);
      expect(second.blockers.join(' '), contains('already exists'));
    },
    timeout: _e2eTimeout,
  );

  test('upgrading to the pinned revision is a no-op', () async {
    final fixture = _createFixture();
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    final result = await runUpgradeCore(
      productRepo: fixture.productRepo,
      targetRevision: fixture.revA,
    );

    expect(result.family, ResultFamily.upgradeNoop);
  }, timeout: _e2eTimeout);

  test('scratch state is discarded on success and on failure', () async {
    final before = _scratchDirPaths();

    final success = _createFixture();
    addTearDown(() => success.root.deleteSync(recursive: true));
    await _runUpgrade(success);
    expect(
      _newScratchDirs(before),
      isEmpty,
      reason: 'a successful upgrade must not leave scratch state',
    );

    // Failure path: target revision that the framework source does not contain.
    // The render source is the sandbox framework, so this stays hermetic — the
    // engine must not fall back to the network to look for an absent revision.
    final failure = _createFixture();
    addTearDown(() => failure.root.deleteSync(recursive: true));
    final result = await _runUpgrade(
      failure,
      targetRevision: '0000000000000000000000000000000000000000',
    );
    expect(result.family, ResultFamily.upgradeBlocked);
    expect(
      result.blockers.join(' '),
      contains(failure.frameworkRepo.path),
      reason:
          'the failure must come from the sandbox framework source, not '
          'from a clone of the canonical network source',
    );
    expect(
      result.blockers.join(' '),
      isNot(contains('github.com')),
      reason: 'no test may reach the network',
    );
    expect(
      _newScratchDirs(before),
      isEmpty,
      reason: 'a failed upgrade must not leave scratch state',
    );
  }, timeout: _e2eTimeout);

  test(
    'an unsupported git version is refused before anything is cloned',
    () async {
      final before = _scratchDirPaths();
      final fixture = _createFixture();
      addTearDown(() => fixture.root.deleteSync(recursive: true));

      // Scratch directories that exist at the moment the gate is probed. Tests
      // inside one file run sequentially, so anything here was created by this
      // call before the gate ran.
      final scratchAtProbe = <String>[];
      final branch =
          'framework/upgrade-${fixture.revA.substring(0, 12)}-'
          '${fixture.revB.substring(0, 12)}';

      final result = await runUpgradeCore(
        productRepo: fixture.productRepo,
        targetRevision: fixture.revB,
        frameworkRootOverride: fixture.frameworkRepo.path,
        // Only the machine's git version is faked; everything else is the real
        // engine, so this exercises the gate itself.
        gitVersionSupported: () {
          scratchAtProbe.addAll(_newScratchDirs(before).map((dir) => dir.path));
          return false;
        },
      );

      expect(result.family, ResultFamily.upgradeBlocked);
      expect(result.humanActionRequired, isTrue);
      expect(result.blockers.join(' '), contains('git >= 2.38'));
      expect(
        scratchAtProbe,
        isEmpty,
        reason: 'the version gate must run before the scratch clone exists',
      );
      expect(
        _git(fixture.productRepo, [
          'rev-parse',
          '--verify',
          '--quiet',
          'refs/heads/$branch',
        ]).exitCode,
        isNot(0),
        reason: 'nothing may be delivered when the git version is unsupported',
      );
    },
    timeout: _e2eTimeout,
  );

  test(
    'an upgrade branch that exists only on the remote is refused up front',
    () async {
      final fixture = _createFixture();
      addTearDown(() => fixture.root.deleteSync(recursive: true));
      final branch =
          'framework/upgrade-${fixture.revA.substring(0, 12)}-'
          '${fixture.revB.substring(0, 12)}';

      // Visible only as a remote-tracking ref: the local branch does not exist, so
      // probing only refs/heads would let the push fail later as a
      // non-fast-forward.
      _gitOut(fixture.productRepo, [
        'update-ref',
        'refs/remotes/origin/$branch',
        'HEAD',
      ]);

      final result = await _runUpgrade(fixture);

      expect(result.family, ResultFamily.upgradeBlocked);
      expect(result.humanActionRequired, isTrue);
      expect(result.blockers.join(' '), contains('already exists'));
      expect(
        result.blockers.join(' '),
        contains('refs/remotes/origin/$branch'),
      );
    },
    timeout: _e2eTimeout,
  );

  test('a copied artifact is an add, not a rename of the file that still '
      'exists', () async {
    // Upstream copies the *old* content of AGENTS.md to a new path and edits
    // AGENTS.md itself. Content alone cannot tell this from a rename, but the
    // base path is still rendered at revision B, so it was never moved: pairing
    // them would erase AGENTS.md's own upstream change from the report.
    final fixture = _createFixture(
      incomingFiles: {
        'AGENTS.md': 'line one\nshared line\nline three\nupstream line\n',
        'docs/engineering/LEGACY.md': _baseFiles['AGENTS.md']!,
      },
    );
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    final result = await _runUpgrade(fixture);

    expect(
      result.family,
      ResultFamily.upgradeReadyForReview,
      reason: '${result.message} ${result.blockers}',
    );
    expect(result.message, contains('Renamed: 0'));
    expect(result.message, contains('Added: 1'));

    final branch =
        'framework/upgrade-${fixture.revA.substring(0, 12)}-'
        '${fixture.revB.substring(0, 12)}';
    expect(
      _fileOnBranch(fixture, branch, 'AGENTS.md'),
      'line one\nshared line\nline three\nupstream line\n',
      reason: 'the file that still exists must receive its own upstream change',
    );
    expect(
      _fileOnBranch(fixture, branch, 'docs/engineering/LEGACY.md'),
      _baseFiles['AGENTS.md'],
    );
  }, timeout: _e2eTimeout);

  test(
    'a framework artifact the product ignores is still merged in',
    () async {
      // The render ships a `.gitignore` that excludes `.claude/`, and ships
      // `.claude/` itself. The product carries both from revision A, so the path
      // the framework now changes is a path the product's ignore rules exclude.
      const ignored = '.claude/settings.json';
      final fixture = _createFixture(
        baseFiles: {
          ..._baseFiles,
          '.gitignore': '.claude/\n',
          ignored: 'claude adapter v1\n',
        },
        incomingFiles: const {
          ignored: 'claude adapter v2\n',
          'docs/engineering/ROADMAP.md': 'upstream roadmap\n',
        },
      );
      addTearDown(() => fixture.root.deleteSync(recursive: true));

      final result = await _runUpgrade(fixture);

      expect(
        result.family,
        ResultFamily.upgradeReadyForReview,
        reason: '${result.message} ${result.blockers}',
      );

      // The ignore rule is real, so this is not a vacuous test: staging the render
      // without `-f` would silently drop the artifact from the merge input.
      // `--no-index` because the product tracks the path, and check-ignore does
      // not report a tracked path as ignored.
      expect(
        _git(fixture.productRepo, [
          'check-ignore',
          '--no-index',
          '-q',
          ignored,
        ]).exitCode,
        0,
        reason: 'the product .gitignore really does exclude $ignored',
      );

      final branch =
          'framework/upgrade-${fixture.revA.substring(0, 12)}-'
          '${fixture.revB.substring(0, 12)}';
      expect(
        _fileOnBranch(fixture, branch, ignored),
        'claude adapter v2\n',
        reason:
            'an ignored framework artifact must still get the upstream '
            'change',
      );
      expect(_fileOnBranch(fixture, branch, '.gitignore'), '.claude/\n');
      expect(
        _fileOnBranch(fixture, branch, 'docs/engineering/ROADMAP.md'),
        'upstream roadmap\n',
      );
      expect(_gitOut(fixture.productRepo, ['status', '--porcelain']), isEmpty);
    },
    timeout: _e2eTimeout,
  );

  test('upgrade never writes into the product working tree', () async {
    final fixture = _createFixture(
      incomingFiles: {'docs/engineering/ROADMAP.md': 'upstream roadmap\n'},
    );
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    await _runUpgrade(fixture);

    expect(_gitOut(fixture.productRepo, ['status', '--porcelain']), isEmpty);
    final manifestOnDisk = File(
      '${fixture.productRepo.path}/framework-manifest.yaml',
    ).readAsStringSync();
    expect(
      FrameworkManifest.parse(manifestOnDisk).revision,
      fixture.revA,
      reason: 'the delivered branch carries the new pin, not the working tree',
    );
    // No stray patch file was left behind (which would break the next preflight).
    expect(
      fixture.productRepo.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.patch'),
      ),
      isEmpty,
    );
  }, timeout: _e2eTimeout);

  test(
    'previous product revision stays reachable from the delivered commit',
    () async {
      final fixture = _createFixture(
        incomingFiles: {'docs/engineering/ROADMAP.md': 'upstream roadmap\n'},
      );
      addTearDown(() => fixture.root.deleteSync(recursive: true));

      await _runUpgrade(fixture);
      final branch =
          'framework/upgrade-${fixture.revA.substring(0, 12)}-'
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
    },
    timeout: _e2eTimeout,
  );

  test(
    'an abbreviated target pins the full revision in the refreshed manifest',
    () async {
      final fixture = _createFixture(
        incomingFiles: const {
          'docs/engineering/ROADMAP.md': 'upstream roadmap\n',
        },
      );
      addTearDown(() => fixture.root.deleteSync(recursive: true));

      await _runUpgrade(fixture, targetRevision: fixture.revB.substring(0, 12));

      final branch =
          'framework/upgrade-${fixture.revA.substring(0, 12)}-'
          '${fixture.revB.substring(0, 12)}';
      final manifest = _fileOnBranch(
        fixture,
        branch,
        'framework-manifest.yaml',
      );

      expect(
        FrameworkManifest.parse(manifest).revision,
        fixture.revB,
        reason: 'the product must be pinned to an unambiguous object id',
      );
    },
    timeout: _e2eTimeout,
  );

  test(
    'brick staging copies are removed from the delivered tree and reported',
    () async {
      final fixture = _createStagingFixture();
      addTearDown(() => fixture.root.deleteSync(recursive: true));

      final result = await _runUpgrade(fixture);
      final branch =
          'framework/upgrade-${fixture.revA.substring(0, 12)}-'
          '${fixture.revB.substring(0, 12)}';
      final reason = 'upgrade result: ${result.message} ${result.blockers}';

      // No fabricated conflict: the copies were never a human-authored rename.
      expect(result.family, ResultFamily.upgradeReadyForReview, reason: reason);
      expect(result.message, contains('Adopted the incoming render: yes'));
      expect(result.blockers.join('\n'), contains('no render of'));
      expect(
        result.humanActionRequired,
        isTrue,
        reason:
            'accepting the removal of framework build inputs is a human '
            'decision',
      );
      expect(
        result.blockers.join('\n'),
        allOf(contains('brick staging artifact'), contains('brick.yaml')),
      );

      final delivered = _gitOut(fixture.productRepo, [
        'ls-tree',
        '-r',
        '--name-only',
        branch,
      ]).split('\n');
      expect(
        delivered.where((p) => p.startsWith('__brick__/')),
        isEmpty,
        reason: "the brick's own __brick__ directory must not reach a product",
      );
      for (final staged in _brickStagedFiles.keys) {
        expect(
          delivered,
          isNot(contains(staged)),
          reason: '$staged is brick build input, not product content',
        );
      }

      // The render itself is still delivered.
      expect(delivered, contains('agents/implementer.md'));
      expect(
        _fileOnBranch(fixture, branch, 'agents/implementer.md'),
        'implementer agent v2\n',
      );

      // And the product working tree is untouched: removal is only a proposal.
      expect(
        File('${fixture.productRepo.path}/__brick__/AGENTS.md').existsSync(),
        isTrue,
      );
      expect(_gitOut(fixture.productRepo, ['status', '--porcelain']), isEmpty);
    },
    timeout: _e2eTimeout,
  );

  test('a product with its own customized artifact conflicts on that artifact '
      'only, and still receives the whole render', () async {
    // The real shape: no render was ever delivered, but the product owns an
    // `AGENTS.md` of its own. Merging against the fictional base would report
    // every framework path as a local deletion; adopting the render must instead
    // conflict on exactly the artifact the product and the framework both own.
    final fixture = _createStagingFixture(
      productOwnFiles: const {'AGENTS.md': _customizedAgents},
    );
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    final result = await _runUpgrade(fixture);
    final branch =
        'framework/upgrade-${fixture.revA.substring(0, 12)}-'
        '${fixture.revB.substring(0, 12)}';

    expect(
      result.family,
      ResultFamily.upgradeConflict,
      reason: '${result.message} ${result.blockers}',
    );
    expect(
      result.blockers.first,
      allOf(contains('1 conflict'), contains('AGENTS.md')),
    );
    expect(result.message, isNot(contains('agents/implementer.md')));

    final delivered = _gitOut(fixture.productRepo, [
      'ls-tree',
      '-r',
      '--name-only',
      branch,
    ]).split('\n');
    expect(delivered, contains('agents/implementer.md'));
    expect(delivered, contains('docs/engineering/WORK_STATE.md'));
    expect(_fileOnBranch(fixture, branch, 'AGENTS.md'), contains('<<<<<<<'));
  }, timeout: _e2eTimeout);

  test(
    'a staging-shaped file the product actually owns is not removed',
    () async {
      final fixture = _createStagingFixture(
        // The product wrote its own README: same name as a brick input, different
        // content, so it is product content and must survive untouched.
        productStagingOverrides: const {'README.md': 'our own readme\n'},
      );
      addTearDown(() => fixture.root.deleteSync(recursive: true));

      final result = await _runUpgrade(fixture);
      final branch =
          'framework/upgrade-${fixture.revA.substring(0, 12)}-'
          '${fixture.revB.substring(0, 12)}';

      final stagingBlocker = result.blockers
          .where((b) => b.contains('brick staging artifact'))
          .join('\n');
      expect(
        stagingBlocker,
        isNot(contains('README.md')),
        reason: 'the product owns this file; the brick merely ships one too',
      );
      expect(_fileOnBranch(fixture, branch, 'README.md'), 'our own readme\n');

      // Preserving the file is only half the contract: the manifest must stop
      // claiming a framework artifact the framework never ships, and the drop must
      // be reported so a human can decide what the entry was.
      final manifest = FrameworkManifest.parse(
        _fileOnBranch(fixture, branch, 'framework-manifest.yaml'),
      );
      expect(
        manifest.managedPaths,
        isNot(contains('README.md')),
        reason: 'a product-owned file is not a framework-managed artifact',
      );
      expect(
        manifest.managedPaths,
        contains('agents/implementer.md'),
        reason: 'the render the product does adopt is still managed',
      );

      final staleBlocker = result.blockers
          .where((b) => b.contains('manifest entr'))
          .join('\n');
      expect(
        staleBlocker,
        isNotEmpty,
        reason:
            'a stale manifest entry must be reported, never silently dropped',
      );
      expect(staleBlocker, contains('README.md'));
    },
    timeout: _e2eTimeout,
  );

  group('git remote identity normalization', () {
    const expected = 'github.com/shipitinc/agentic-engineering-framework';

    test('every spelling of the approved repository normalizes identically', () {
      const spellings = [
        'https://github.com/shipitinc/agentic-engineering-framework.git',
        'https://github.com/shipitinc/agentic-engineering-framework',
        'https://github.com/shipitinc/agentic-engineering-framework/',
        'https://token@github.com/shipitinc/agentic-engineering-framework.git',
        'https://user:password@github.com:8443'
            '/shipitinc/agentic-engineering-framework.git',
        'http://github.com/shipitinc/agentic-engineering-framework.git',
        'ssh://git@github.com/shipitinc/agentic-engineering-framework.git',
        'git://github.com/shipitinc/agentic-engineering-framework.git',
        'https://GitHub.com/shipitinc/agentic-engineering-framework.git',
        'git@github.com:shipitinc/agentic-engineering-framework.git',
        'github.com:shipitinc/agentic-engineering-framework.git',
      ];
      for (final url in spellings) {
        expect(normalizeRemoteIdentity(url), expected, reason: url);
      }
      expect(
        normalizeRemoteIdentity(approvedFrameworkSource),
        expected,
        reason: 'the gate compares against the approved source itself',
      );
    });

    test('a different repository or a non-remote is not that identity', () {
      const rejected = [
        'https://github.com/evil/agentic-engineering-framework.git',
        'https://github.com/shipitinc/agentic-engineering-frameworkX.git',
        'https://github.com/shipitinc/agentic-engineering',
        'https://evil.example.com/shipitinc/agentic-engineering-framework.git',
        'git@github.com:evil/agentic-engineering-framework.git',
        // A local path is not a repository identity and must never satisfy the
        // trusted-source check.
        '/Users/me/src/agentic-engineering-framework',
        './agentic-engineering-framework',
        'file:///Users/me/src/agentic-engineering-framework.git',
        '',
        '   ',
      ];
      for (final url in rejected) {
        expect(normalizeRemoteIdentity(url), isNot(expected), reason: '"$url"');
      }
    });
  });
}

extension on String {
  void let(void Function(String) action) => action(this);
}
