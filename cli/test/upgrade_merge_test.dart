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
/// `PROVENANCE.md` carries the framework's own `{{frameworkRevision}}`
/// substitution, the managed provenance line the framework renders.
const _baseFiles = <String, String>{
  'AGENTS.md': 'line one\nshared line\nline three\nline four\n',
  'docs/engineering/WORK_STATE.md': 'base work state\n',
  'PROVENANCE.md': 'Framework revision: {{frameworkRevision}}\n',
};

/// The locally customized copy of `AGENTS.md` used by several tests.
const _customizedAgents =
    'product customized agents\nshared line\nline three\nline four\n';

class _Fixture {
  _Fixture({
    required this.root,
    required this.frameworkRepo,
    required this.productRepo,
    required this.remote,
    required this.revA,
    required this.revB,
    this.revC,
  });

  final Directory root;
  final Directory frameworkRepo;
  final Directory productRepo;

  /// The product repository's real remote, a bare repository. Delivery must land
  /// here and nowhere else.
  final Directory remote;

  final String revA;
  final String revB;

  /// A third framework revision, used to prove that a second upgrade of a
  /// product that already carries a provenance pin is still clean.
  final String? revC;
}

/// Creates the product repository's remote as a real bare repository.
///
/// A directory that is not a git repository would make delivery untestable: a
/// push that reached it would fail, and a push that did not would pass unnoticed.
Directory _createBareRemote(String rootPath, String name) {
  final remote = Directory('$rootPath/$name')..createSync(recursive: true);
  final init = _git(remote, ['init', '-q', '--bare', '-b', 'main', '.']);
  if (init.exitCode != 0) {
    throw StateError('could not create the fixture remote: ${init.stderr}');
  }
  return remote;
}

/// Builds a framework repo with two revisions and a product repo bootstrapped
/// from [revA]. [baseFiles] are the `__brick__` files at [revA];
/// [incomingFiles] are the `__brick__` files added or changed at [revB];
/// [productFiles] are extra product-owned files added on top of the render.
///
/// When [withThirdRevision] is set, [thirdRevisionFiles] are committed as a third
/// framework revision so a test can run a second, sequential upgrade.
_Fixture _createFixture({
  Map<String, String> baseFiles = _baseFiles,
  Map<String, String> incomingFiles = const {},
  Map<String, String> productFiles = const {},
  List<String> removedAtIncoming = const [],
  Map<String, String> productOverlays = const {},
  bool withThirdRevision = false,
  Map<String, String> thirdRevisionFiles = const {},
}) {
  final root = Directory.systemTemp.createTempSync('aef_fixture_');
  final frameworkRepo = Directory('${root.path}/framework')..createSync();
  final productRepo = Directory('${root.path}/product')..createSync();
  final remote = _createBareRemote(root.path, 'remote.git');

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

  String? revC;
  if (withThirdRevision) {
    // Always a real change, so the third revision is a distinct commit.
    _writeBrick(frameworkRepo, <String, String>{
      ...nextBrick,
      ...thirdRevisionFiles,
    });
    _git(frameworkRepo, ['add', '-A', '-f']);
    _git(frameworkRepo, ['commit', '-qm', 'framework revision C']);
    revC = _gitOut(frameworkRepo, ['rev-parse', 'HEAD']);
  }

  // Product repository: revision A rendered, plus the product's own files and
  // its committed local customizations of managed artifacts — which is what a
  // real product looks like, and what the dirty-tree guard permits.
  _git(productRepo, ['init', '-q', '-b', 'main', '.']);
  _configureIdentity(productRepo);
  _git(productRepo, ['remote', 'add', 'origin', remote.absolute.path]);
  // Bootstrap substitutes the framework revision with the resolved object id, so
  // the product's copy of a rendered file carries exactly that. Reproducing it
  // here is what makes the merge base equal to what the product already has.
  _renderInto(productRepo, baseFiles, vars: {'frameworkRevision': revA});
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
    remote: remote,
    revA: revA,
    revB: revB,
    revC: revC,
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
  final remote = _createBareRemote(root.path, 'remote.git');

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
  _git(productRepo, ['remote', 'add', 'origin', remote.absolute.path]);
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
    remote: remote,
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

/// Mirrors what a Mason render of the brick produces in a product repository:
/// every file, with `{{var}}` placeholders substituted the way the CLI
/// substitutes them.
void _renderInto(
  Directory target,
  Map<String, String> files, {
  Map<String, String> vars = const {},
}) {
  files.forEach(
    (path, content) => _writeFile(target, path, _substituteVars(content, vars)),
  );
}

String _substituteVars(String content, Map<String, String> vars) {
  var result = content;
  vars.forEach((name, value) {
    result = result.replaceAll('{{$name}}', value);
  });
  return result;
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

/// Reproduces what the pre-repair engine delivered to a real product: the
/// provenance pin abbreviated in every rendered file, while the manifest keeps
/// the full object id. [extraEdits] are applied on top, to represent genuine
/// product customizations of the same files.
void _abbreviateProductPin(
  _Fixture fixture, {
  Map<String, String> appended = const {},
}) {
  final shortPin = fixture.revA.substring(0, 7);
  for (final entity in fixture.productRepo.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final relative = entity.path.substring(fixture.productRepo.path.length + 1);
    // The manifest is not part of this: it pins the resolved object id, which is
    // exactly what made the delivered file disagree with it.
    if (relative == 'framework-manifest.yaml' || relative.startsWith('.git/')) {
      continue;
    }
    final text = entity.readAsStringSync();
    if (!text.contains(fixture.revA)) continue;
    entity.writeAsStringSync(text.replaceAll(fixture.revA, shortPin));
  }
  appended.forEach((path, text) {
    final file = File('${fixture.productRepo.path}/$path');
    file.writeAsStringSync('${file.readAsStringSync()}$text');
  });
  _git(fixture.productRepo, ['add', '-A', '-f']);
  _git(fixture.productRepo, [
    'commit',
    '-qm',
    'product abbreviates its provenance pin',
  ]);
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

/// The branch name the engine delivers for an `revisionA -> revisionB` upgrade.
String _branchFor(String revisionA, String revisionB) =>
    'framework/upgrade-${revisionA.substring(0, 12)}-${revisionB.substring(0, 12)}';

/// Object id [ref] resolves to in the product repository's **remote**, or null
/// when the remote does not have it.
///
/// Read from the bare repository itself rather than through the product, so an
/// assertion about "the remote has it" cannot be satisfied by a ref that only
/// exists in the product's local store.
String? _remoteHead(_Fixture fixture, String ref) {
  final probe = _git(fixture.remote, ['rev-parse', '--verify', '--quiet', ref]);
  if (probe.exitCode != 0) return null;
  return (probe.stdout as String).trim();
}

/// Accepts the delivered upgrade branch into the product's `main`, the way a
/// human does after reviewing it.
void _acceptUpgrade(_Fixture fixture, String branch) {
  _gitOut(fixture.productRepo, ['merge', '--ff-only', branch]);
}

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
    'the upgrade branch is delivered to the product real remote',
    () async {
      // The scratch clone's origin is the product's *local path*, so a push from
      // there exits 0, writes a ref into the product repository, and reaches the
      // hosting provider of nothing. Asserting against the product's local store
      // cannot tell the two apart; asserting against the real remote can.
      final fixture = _createFixture(
        incomingFiles: const {
          'docs/engineering/ROADMAP.md': 'upstream roadmap\n',
        },
      );
      addTearDown(() => fixture.root.deleteSync(recursive: true));
      final branch = _branchFor(fixture.revA, fixture.revB);

      final result = await _runUpgrade(fixture);

      expect(
        result.family,
        ResultFamily.upgradeReadyForReview,
        reason: 'upgrade result: ${result.message} ${result.blockers}',
      );

      // The remote really is a repository, so "it is not there" is evidence.
      expect(
        _gitOut(fixture.remote, ['rev-parse', '--is-bare-repository']),
        'true',
      );

      final localHead = _gitOut(fixture.productRepo, ['rev-parse', branch]);
      expect(
        _remoteHead(fixture, 'refs/heads/$branch'),
        localHead,
        reason:
            'the delivered commit must exist on the product remote, not only '
            'in the product local store',
      );
      expect(
        _gitOut(fixture.remote, ['rev-parse', '$localHead^']),
        _gitOut(fixture.productRepo, ['rev-parse', 'HEAD']),
        reason:
            'the delivered commit is one commit on the product real history',
      );
      expect(
        result.message,
        contains(fixture.remote.absolute.path),
        reason: 'the result must say where the branch was delivered',
      );

      // The local review branch exists too, so the review command the result
      // reports resolves by the bare branch name.
      expect(_gitOut(fixture.productRepo, ['status', '--porcelain']), isEmpty);
      expect(
        _gitOut(fixture.productRepo, ['diff', '--stat', 'HEAD..$branch']),
        isNotEmpty,
      );

      // The transient ref the commit travelled under is gone: delivery must not
      // leave a second, unnameable handle on the merged tree behind.
      expect(
        _gitOut(fixture.productRepo, [
          'for-each-ref',
          '--format=%(refname)',
          'refs/aef-upgrade/',
        ]),
        isEmpty,
      );
    },
    timeout: _e2eTimeout,
  );

  test(
    'a product with no delivery remote is blocked before any work',
    () async {
      final fixture = _createFixture();
      addTearDown(() => fixture.root.deleteSync(recursive: true));
      _gitOut(fixture.productRepo, ['remote', 'remove', 'origin']);

      final result = await _runUpgrade(fixture);

      expect(result.family, ResultFamily.upgradeBlocked);
      expect(result.humanActionRequired, isTrue);
      expect(result.blockers.join(' '), contains('origin'));
      // Refused before anything was created: no branch anywhere.
      final branch = _branchFor(fixture.revA, fixture.revB);
      expect(
        _git(fixture.productRepo, [
          'show-ref',
          '--verify',
          '--quiet',
          'refs/heads/$branch',
        ]).exitCode,
        isNot(0),
      );
      expect(_remoteHead(fixture, 'refs/heads/$branch'), isNull);
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

  test(
    'an upgrade branch that exists on the real remote is refused up front',
    () async {
      // The state a real product is in after a previous run: the branch was
      // delivered, so it is on the remote, and nothing local refers to it. Probing
      // only local refs cannot see this, and the push would then land on top of a
      // review that is still in progress.
      final fixture = _createFixture();
      addTearDown(() => fixture.root.deleteSync(recursive: true));
      final branch = _branchFor(fixture.revA, fixture.revB);

      // Pushed to the remote by URL: a push by URL leaves no ref of its own behind in
      // the product, which is exactly the state under test — the branch is only
      // on the remote.
      final productHead = _gitOut(fixture.productRepo, ['rev-parse', 'HEAD']);
      _gitOut(fixture.productRepo, [
        'push',
        fixture.remote.absolute.path,
        '$productHead:refs/heads/$branch',
      ]);
      expect(
        _git(fixture.productRepo, [
          'show-ref',
          '--verify',
          '--quiet',
          'refs/heads/$branch',
        ]).exitCode,
        isNot(0),
        reason: 'the product itself has no local ref for the branch',
      );
      expect(
        _git(fixture.productRepo, [
          'show-ref',
          '--verify',
          '--quiet',
          'refs/remotes/origin/$branch',
        ]).exitCode,
        isNot(0),
        reason:
            'nor is there a remote-tracking ref, so only the remote probe '
            'can see this branch',
      );

      final result = await _runUpgrade(fixture);

      expect(result.family, ResultFamily.upgradeBlocked);
      expect(result.humanActionRequired, isTrue);
      expect(result.blockers.join(' '), contains('already exists'));
      expect(result.blockers.join(' '), contains('refs/heads/$branch'));
      expect(
        _remoteHead(fixture, 'refs/heads/$branch'),
        _gitOut(fixture.productRepo, ['rev-parse', 'HEAD']),
        reason: 'the review in progress must not be overwritten',
      );
    },
    timeout: _e2eTimeout,
  );

  test(
    'an unreadable remote is refused rather than assumed branch-free',
    () async {
      // "The remote could not be asked" is not evidence that the branch is absent,
      // and the upgrade's job is to never overwrite a review in progress.
      final fixture = _createFixture();
      addTearDown(() => fixture.root.deleteSync(recursive: true));
      _gitOut(fixture.productRepo, [
        'remote',
        'set-url',
        'origin',
        '${fixture.root.path}/does-not-exist',
      ]);

      final result = await _runUpgrade(fixture);

      expect(result.family, ResultFamily.upgradeBlocked);
      expect(result.humanActionRequired, isTrue);
      expect(result.blockers.join(' '), contains('cannot be checked'));
      expect(result.blockers.join(' '), contains('does-not-exist'));
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

  test('the rendered provenance pin is the resolved revision, and the manifest '
      'records it', () async {
    // An abbreviated target must not become the provenance identifier the
    // product's artifacts carry: the rendered line has to be the same immutable
    // object id the manifest pins, whatever was typed on the command line.
    final fixture = _createFixture(
      incomingFiles: const {
        'docs/engineering/ROADMAP.md': 'upstream roadmap\n',
      },
    );
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    await _runUpgrade(fixture, targetRevision: fixture.revB.substring(0, 12));
    final branch = _branchFor(fixture.revA, fixture.revB);

    expect(
      _fileOnBranch(fixture, branch, 'PROVENANCE.md'),
      'Framework revision: ${fixture.revB}\n',
      reason: 'the render must carry the resolved object id',
    );

    final manifest = FrameworkManifest.parse(
      _fileOnBranch(fixture, branch, 'framework-manifest.yaml'),
    );
    expect(manifest.revision, fixture.revB);
    expect(
      manifest.templateInputs['frameworkRevision'],
      fixture.revB,
      reason:
          'template_inputs records the value the render substituted, so a '
          'carried-forward instantiation pin is not a false record',
    );
  }, timeout: _e2eTimeout);

  test(
    'a second upgrade of a product that already carries a pin is clean',
    () async {
      // The sequence that produced the conflict this replaces: upgrade with an
      // abbreviated target, accept it, then upgrade again. The provenance line has
      // exactly one legitimate change per upgrade — a one-sided pin bump. It
      // conflicts only if the delivered line is not the same identifier the next
      // base render resolves to.
      final fixture = _createFixture(
        withThirdRevision: true,
        thirdRevisionFiles: const {
          'docs/engineering/UPGRADE_NOTES.md': 'notes at revision C\n',
        },
      );
      addTearDown(() => fixture.root.deleteSync(recursive: true));
      final revC = fixture.revC!;

      final first = await _runUpgrade(
        fixture,
        targetRevision: fixture.revB.substring(0, 12),
      );
      expect(
        first.family,
        ResultFamily.upgradeReadyForReview,
        reason: 'first upgrade: ${first.message} ${first.blockers}',
      );
      _acceptUpgrade(fixture, _branchFor(fixture.revA, fixture.revB));
      expect(
        File('${fixture.productRepo.path}/PROVENANCE.md').readAsStringSync(),
        'Framework revision: ${fixture.revB}\n',
        reason: 'the accepted branch is what the product now carries',
      );

      final second = await _runUpgrade(
        fixture,
        targetRevision: revC.substring(0, 12),
      );

      expect(
        second.family,
        ResultFamily.upgradeReadyForReview,
        reason: 'second upgrade: ${second.message} ${second.blockers}',
      );
      expect(second.blockers.join('\n'), isNot(contains('conflict')));
      expect(second.message, contains('Conflicts: 0'));
      expect(
        _fileOnBranch(fixture, _branchFor(fixture.revB, revC), 'PROVENANCE.md'),
        'Framework revision: $revC\n',
      );
    },
    timeout: _e2eTimeout,
  );

  test(
    'an upgrade whose every change is a one-sided upstream edit is not a no-op',
    () async {
      // The delivered branch is real work in this case, so reporting a no-op
      // after pushing it would tell the human there is nothing to review.
      final fixture = _createFixture(
        withThirdRevision: true,
        thirdRevisionFiles: const {
          'docs/engineering/WORK_STATE.md': 'work state at revision C\n',
        },
      );
      addTearDown(() => fixture.root.deleteSync(recursive: true));
      final revC = fixture.revC!;
      await _runUpgrade(fixture, targetRevision: fixture.revB);
      _acceptUpgrade(fixture, _branchFor(fixture.revA, fixture.revB));

      final result = await _runUpgrade(fixture, targetRevision: revC);

      expect(
        result.family,
        ResultFamily.upgradeReadyForReview,
        reason: '${result.message} ${result.blockers}',
      );
      expect(
        result.message,
        contains('Modified: 2'),
        reason:
            'both one-sided edits count: the work state text, and the '
            'provenance pin, which changes on every upgrade by construction',
      );
      expect(
        _fileOnBranch(
          fixture,
          _branchFor(fixture.revB, revC),
          'docs/engineering/WORK_STATE.md',
        ),
        'work state at revision C\n',
      );
    },
    timeout: _e2eTimeout,
  );

  test(
    'a product whose pin was delivered abbreviated upgrades without conflict',
    () async {
      // What a consumer actually hit: the delivered file said `e37b2a3` while
      // the manifest pinned `e37b2a3fa344…`. Both name one commit, so this is
      // not a competing edit and must not be adjudicated as one.
      const pinFiles = <String, String>{
        'PROVENANCE.md': 'Framework revision: {{frameworkRevision}}\n',
        'docs/engineering/PIN.md':
            'Framework revision: {{frameworkRevision}}\n',
      };
      final fixture = _createFixture(
        baseFiles: {..._baseFiles, ...pinFiles},
        withThirdRevision: true,
        thirdRevisionFiles: const {'CHANGELOG.md': 'revision C\n'},
      );
      addTearDown(() => fixture.root.deleteSync(recursive: true));
      final revC = fixture.revC!;
      _abbreviateProductPin(fixture);
      expect(
        File('${fixture.productRepo.path}/PROVENANCE.md').readAsStringSync(),
        'Framework revision: ${fixture.revA.substring(0, 7)}\n',
        reason: 'the fixture must reproduce the abbreviated delivery',
      );

      final result = await _runUpgrade(fixture, targetRevision: fixture.revB);

      expect(
        result.family,
        ResultFamily.upgradeReadyForReview,
        reason: '${result.message} ${result.blockers}',
      );
      expect(result.blockers.join('\n'), isNot(contains('conflict')));
      expect(result.message, contains('Conflicts: 0'));
      expect(
        result.message,
        contains('Provenance pin spellings canonicalized: 2'),
        reason: 'the normalization is reported, never silent',
      );
      final branch = _branchFor(fixture.revA, fixture.revB);
      for (final path in pinFiles.keys) {
        expect(
          _fileOnBranch(fixture, branch, path),
          'Framework revision: ${fixture.revB}\n',
          reason: '$path carried the pin abbreviated and must now carry the id',
        );
      }
      // The next upgrade must be clean too: the delivered tree is the one the
      // next base render reproduces exactly.
      _acceptUpgrade(fixture, branch);
      final second = await _runUpgrade(
        fixture,
        targetRevision: revC.substring(0, 12),
      );
      expect(
        second.family,
        ResultFamily.upgradeReadyForReview,
        reason: 'follow-up upgrade: ${second.message} ${second.blockers}',
      );
      expect(second.message, contains('Conflicts: 0'));
      expect(
        second.message,
        contains('Provenance pin spellings canonicalized: 0'),
        reason: 'after the repair the pin is spelled the one canonical way',
      );
    },
    timeout: _e2eTimeout,
  );

  test(
    'a pin that is not another spelling of the base id is never canonicalized',
    () async {
      // The rule is "another spelling of the SAME object id", not "any hex
      // string". A product that points the line at a different commit, or at an
      // abbreviation shorter than git's 4-character minimum, is making a claim
      // this must not silently overwrite.
      final fixture = _createFixture(
        baseFiles: {
          ..._baseFiles,
          'PROVENANCE.md': 'Framework revision: {{frameworkRevision}}\n',
          'docs/engineering/PIN.md':
              'Framework revision: {{frameworkRevision}}\n',
        },
      );
      addTearDown(() => fixture.root.deleteSync(recursive: true));
      final foreignPin = 'deadbee${fixture.revA.substring(8)}';
      File(
        '${fixture.productRepo.path}/PROVENANCE.md',
      ).writeAsStringSync('Framework revision: $foreignPin\n');
      File(
        '${fixture.productRepo.path}/docs/engineering/PIN.md',
      ).writeAsStringSync(
        'Framework revision: ${fixture.revA.substring(0, 3)}\n',
      );
      _git(fixture.productRepo, ['add', '-A', '-f']);
      _git(fixture.productRepo, [
        'commit',
        '-qm',
        'product pins something else',
      ]);

      final result = await _runUpgrade(fixture, targetRevision: fixture.revB);

      expect(
        result.family,
        ResultFamily.upgradeConflict,
        reason: '${result.message} ${result.blockers}',
      );
      expect(
        result.message,
        contains('Provenance pin spellings canonicalized: 0'),
        reason:
            'neither a foreign object nor a sub-minimum abbreviation counts',
      );
      expect(result.message, contains('Conflicts: 2'));
    },
    timeout: _e2eTimeout,
  );

  test(
    'an abbreviated pin plus a real local edit still conflicts',
    () async {
      // The negative case that keeps the normalization honest: it applies only to
      // a file that differs from base *solely* by how the pin is spelled. One
      // file has both the abbreviated pin and a genuine local edit, and it must
      // still come back as a conflict with the product's own text intact.
      const pinFiles = <String, String>{
        'PROVENANCE.md': 'Framework revision: {{frameworkRevision}}\n',
        'docs/engineering/PIN.md':
            'Framework revision: {{frameworkRevision}}\n',
      };
      final fixture = _createFixture(baseFiles: {..._baseFiles, ...pinFiles});
      addTearDown(() => fixture.root.deleteSync(recursive: true));
      _abbreviateProductPin(
        fixture,
        appended: const {'PROVENANCE.md': 'local edit\n'},
      );

      final result = await _runUpgrade(fixture, targetRevision: fixture.revB);

      expect(
        result.family,
        ResultFamily.upgradeConflict,
        reason: '${result.message} ${result.blockers}',
      );
      expect(
        result.message,
        contains('Conflicts: 1'),
        reason: 'a genuine local edit is still a conflict, not a rewrite',
      );
      expect(
        result.message,
        contains('Provenance pin spellings canonicalized: 1'),
        reason:
            'only the file whose sole difference was the spelling is repaired',
      );
      final branch = _branchFor(fixture.revA, fixture.revB);
      expect(
        _fileOnBranch(fixture, branch, 'PROVENANCE.md'),
        contains('local edit'),
        reason: "the product's own text must survive verbatim",
      );
      expect(
        _fileOnBranch(fixture, branch, 'docs/engineering/PIN.md'),
        'Framework revision: ${fixture.revB}\n',
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
