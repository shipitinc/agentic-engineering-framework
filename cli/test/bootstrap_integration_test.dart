import 'dart:io';

import 'package:framework_cli/framework_cli.dart';
import 'package:test/test.dart';

/// Integration regression tests for bootstrap defects.
///
/// These tests use a real disposable product repository and run the CLI
/// as a subprocess (via `dart run`) to verify the fixes for:
/// - KNOWN DEFECT A: Managed artifact ownership (pre-existing product files not claimed)
/// - KNOWN DEFECT B: Git internal files exclusion (.git/** never managed)
/// - KNOWN DEFECT C: Revision provenance (framework source revision recorded)
/// - KNOWN DEFECT D: Template completeness (all governance files installed)
/// - Re-run safety (no-op on existing manifest)
void main() {
  group('bootstrap integration regression', () {
    late Directory sandbox;
    late Directory previousCwd;
    final String frameworkRepoPath = '/Users/alkebut/air/agentic-engineering-framework';

    setUp(() {
      previousCwd = Directory.current;
      sandbox = Directory.systemTemp.createTempSync('framework_bootstrap_test_');
      Directory.current = sandbox;
    });

    tearDown(() {
      Directory.current = previousCwd;
      if (sandbox.existsSync()) {
        sandbox.deleteSync(recursive: true);
      }
    });

    /// Creates a fresh product repo with pre-existing files and .git directory.
    Future<Directory> createProductRepoWithPreExistingFiles() async {
      final productDir = Directory('${sandbox.path}/product');
      productDir.createSync(recursive: true);

      // Initialize git repo in product directory
      Process.runSync('git', ['init'], workingDirectory: productDir.path);
      Process.runSync('git', ['config', 'user.email', 'test@example.com'],
          workingDirectory: productDir.path);
      Process.runSync('git', ['config', 'user.name', 'Test User'],
          workingDirectory: productDir.path);

      // Create pre-existing product files
      File('${productDir.path}/product-only.txt').writeAsStringSync('product only content');
      Directory('${productDir.path}/src').createSync(recursive: true);
      File('${productDir.path}/src/existing.dart').writeAsStringSync('// existing dart file');
      File('${productDir.path}/README-product.md').writeAsStringSync('# Product README');

      // Commit pre-existing files
      Process.runSync('git', ['add', '.'], workingDirectory: productDir.path);
      Process.runSync('git', ['commit', '-m', 'Initial product commit'],
          workingDirectory: productDir.path);

      return productDir;
    }

    /// Runs bootstrap via `dart run` from the framework repo context.
    Future<void> runBootstrap(Directory targetDir) async {
      final result = await Process.run(
        'dart',
        ['run', 'cli/bin/framework.dart', 'bootstrap', '--target', targetDir.path],
        workingDirectory: frameworkRepoPath,
      );
      expect(result.exitCode, 0, reason: 'Bootstrap should succeed: stdout=${result.stdout}\nstderr=${result.stderr}');
      expect(result.stdout.toString(), contains('BOOTSTRAP_COMPLETE'));
    }

    /// Reads and parses the framework-manifest.yaml from the target directory.
    FrameworkManifest readManifest(Directory targetDir) {
      final manifestFile = File('${targetDir.path}/framework-manifest.yaml');
      expect(manifestFile.existsSync(), isTrue, reason: 'Manifest should exist');
      final yamlText = manifestFile.readAsStringSync();
      return FrameworkManifest.parse(yamlText);
    }

    test('KNOWN DEFECT B: .git/** paths are NEVER in managed artifacts', () async {
      final productDir = await createProductRepoWithPreExistingFiles();
      await runBootstrap(productDir);

      final manifest = readManifest(productDir);

      // Verify no .git/** paths in managed artifacts
      for (final artifact in manifest.artifacts) {
        expect(artifact.path.startsWith('.git/'), isFalse,
            reason: 'Artifact "${artifact.path}" should not be a .git/** path');
      }

      // Verify .git directory exists but is not managed
      expect(Directory('${productDir.path}/.git').existsSync(), isTrue);
    }, timeout: Timeout(Duration(minutes: 2)));

    test('KNOWN DEFECT A: Pre-existing product files are preserved and NOT managed', () async {
      final productDir = await createProductRepoWithPreExistingFiles();
      await runBootstrap(productDir);

      final manifest = readManifest(productDir);

      // Verify pre-existing files still exist
      expect(File('${productDir.path}/product-only.txt').existsSync(), isTrue);
      expect(File('${productDir.path}/src/existing.dart').existsSync(), isTrue);
      expect(File('${productDir.path}/README-product.md').existsSync(), isTrue);

      // Verify pre-existing files are NOT in managed artifacts
      final managedPaths = manifest.managedPaths;
      expect(managedPaths, isNot(contains('product-only.txt')));
      expect(managedPaths, isNot(contains('src/existing.dart')));
      expect(managedPaths, isNot(contains('README-product.md')));
    }, timeout: Timeout(Duration(minutes: 2)));

    test('KNOWN DEFECT C: Manifest records framework source revision, not product revision', () async {
      final productDir = await createProductRepoWithPreExistingFiles();

      // Get product repo HEAD before bootstrap
      final productHeadResult = Process.runSync('git', ['rev-parse', 'HEAD'],
          workingDirectory: productDir.path);
      final productHead = productHeadResult.stdout.toString().trim();

      await runBootstrap(productDir);

      final manifest = readManifest(productDir);

      // Manifest revision should be the framework source revision, not product HEAD
      expect(manifest.revision, isNot(equals(productHead)),
          reason: 'Manifest revision (${manifest.revision}) should not equal product HEAD ($productHead)');

      // Framework revision should be a valid SHA (40 hex chars)
      expect(manifest.revision, matches(RegExp(r'^[a-f0-9]{40}$')));
    }, timeout: Timeout(Duration(minutes: 2)));

    test('KNOWN DEFECT D: Template completeness - all governance files installed', () async {
      final productDir = Directory('${sandbox.path}/product2');
      productDir.createSync(recursive: true);
      Process.runSync('git', ['init'], workingDirectory: productDir.path);
      Process.runSync('git', ['config', 'user.email', 'test@example.com'],
          workingDirectory: productDir.path);
      Process.runSync('git', ['config', 'user.name', 'Test User'],
          workingDirectory: productDir.path);
      Process.runSync('git', ['commit', '--allow-empty', '-m', 'Initial commit'],
          workingDirectory: productDir.path);

      await runBootstrap(productDir);

      final manifest = readManifest(productDir);

      // Verify expected governance files are present
      final expectedPaths = [
        'AGENTS.md',
        'docs/engineering/WORKFLOW.md',
        'docs/engineering/WORK_STATE.md',
        'docs/engineering/LEARNING_POLICY.md',
        'docs/engineering/adr/0001-framework-distribution-and-versioning.md',
        'docs/engineering/adr/0002-dart-mason-git-framework-driver.md',
        '.junie/agents/correction-implementer.md',
        '.junie/agents/engineering-reviewer.md',
        '.junie/agents/focused-reviewer.md',
        '.junie/agents/implementer.md',
        '.junie/agents/integrator.md',
        '.junie/commands/run-feature.md',
        '.junie/skills/correction-loop/SKILL.md',
        '.junie/skills/implementation-workflow/SKILL.md',
        '.junie/skills/independent-review/SKILL.md',
        '.junie/skills/repository-learning/SKILL.md',
      ];

      for (final expectedPath in expectedPaths) {
        expect(manifest.managedPaths, contains(expectedPath),
            reason: 'Expected managed artifact: $expectedPath');
        expect(File('${productDir.path}/$expectedPath').existsSync(), isTrue,
            reason: 'File should exist on disk: $expectedPath');
      }

      // Verify managed artifact count matches expected
      expect(manifest.artifacts.length, expectedPaths.length);
    }, timeout: Timeout(Duration(minutes: 3)));

    test('Re-run safety: bootstrap no-ops when manifest already exists', () async {
      final productDir = await createProductRepoWithPreExistingFiles();
      await runBootstrap(productDir);

      final manifest1 = readManifest(productDir);
      final firstInstantiatedAt = manifest1.instantiatedAt;

      // Run bootstrap again
      await runBootstrap(productDir);

      final manifest2 = readManifest(productDir);

      // Manifest should be unchanged (same instantiation timestamp)
      expect(manifest2.instantiatedAt, equals(firstInstantiatedAt));
      expect(manifest2.revision, equals(manifest1.revision));
      expect(manifest2.artifacts.length, equals(manifest1.artifacts.length));
    }, timeout: Timeout(Duration(minutes: 3)));

    test('Managed artifacts have baseline hashes (source_hash and install_hash)', () async {
      final productDir = await createProductRepoWithPreExistingFiles();
      await runBootstrap(productDir);

      final manifest = readManifest(productDir);

      for (final artifact in manifest.artifacts) {
        expect(artifact.sourceHash.hex, isNotEmpty);
        expect(artifact.installHash.hex, isNotEmpty);
        expect(artifact.sourceHash.algorithm, 'sha256');
        expect(artifact.installHash.algorithm, 'sha256');
        // For bootstrap, source_hash == install_hash (baseline)
        expect(artifact.sourceHash, equals(artifact.installHash));
      }
    }, timeout: Timeout(Duration(minutes: 2)));

    test('Framework source identity recorded in manifest', () async {
      final productDir = await createProductRepoWithPreExistingFiles();
      await runBootstrap(productDir);

      final manifest = readManifest(productDir);

      expect(manifest.source, 'https://github.com/shipitinc/agentic-engineering-framework.git');
      expect(manifest.version, '0.1.0');
    }, timeout: Timeout(Duration(minutes: 2)));

    test('Path safety: managed paths are normalized and safe', () async {
      final productDir = await createProductRepoWithPreExistingFiles();
      await runBootstrap(productDir);

      final manifest = readManifest(productDir);

      for (final artifact in manifest.artifacts) {
        // Paths should be POSIX-style, relative, no ..
        expect(artifact.path, isNot(contains('..')));
        expect(artifact.path, isNot(startsWith('/')));
        expect(artifact.path, isNot(contains('\\')));
        // Should not be empty
        expect(artifact.path, isNotEmpty);
      }
    }, timeout: Timeout(Duration(minutes: 2)));
  });
}