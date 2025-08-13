# Contributing to FSWatcher

Thank you for your interest in contributing to FSWatcher! This guide will help you get started.

## Code of Conduct

By participating in this project, you agree to abide by our Code of Conduct. Please treat all contributors with respect and kindness.

## Getting Started

### Prerequisites

- Xcode 14.0 or later
- Swift 5.9 or later
- macOS 12.0 or later for development

### Setting up the Development Environment

1. Fork the repository on GitHub
2. Clone your fork locally:

   ```bash
   git clone https://github.com/YOUR_USERNAME/FSWatcher.git
   cd FSWatcher
   ```

3. Open the project in Xcode or use Swift Package Manager:

   ```bash
   swift build
   ```

## Development Guidelines

### Code Style

- Follow Swift API Design Guidelines
- Use meaningful variable and function names
- Add documentation comments for all public APIs
- Keep functions focused and concise
- Prefer composition over inheritance

### Example of well-documented code

```swift
/// Creates a new directory watcher for monitoring file system changes.
/// 
/// - Parameters:
///   - url: The directory URL to watch. Must be an existing directory.
///   - configuration: Configuration options for the watcher.
/// - Throws: `FSWatcherError` if the directory cannot be watched.
/// - Returns: A configured directory watcher instance.
public init(url: URL, configuration: Configuration = Configuration()) throws {
    // Implementation here
}
```

### Architecture Principles

1. **Event-driven**: Use DispatchSource for efficient monitoring
2. **Thread-safe**: All public APIs should be thread-safe
3. **Resource management**: Automatic cleanup of system resources
4. **Testable**: Write testable code with dependency injection
5. **Performance**: Optimize for low resource usage

### File Organization

- Core functionality goes in `Sources/FSWatcher/Core/`
- Utility classes in `Sources/FSWatcher/Utils/`
- Extensions in `Sources/FSWatcher/Extensions/`
- Tests in `Tests/FSWatcherTests/`
- Examples in `Examples/`

## Making Changes

### Branch Naming

Use descriptive branch names:

- `feature/recursive-watching`
- `bugfix/memory-leak-in-watcher`
- `docs/api-documentation`

### Commit Messages

Write clear commit messages:

- Use the imperative mood ("Add feature" not "Added feature")
- Keep the first line under 50 characters
- Reference issues when applicable

Example:

```plaintext
Add predictive ignoring for transform operations

This change allows watchers to predict output files based on
transformation rules, preventing infinite loops in processing
pipelines.

Fixes #123
```

### Testing Requirements

All changes must include appropriate tests:

1. **Unit Tests**: Test individual components
2. **Integration Tests**: Test component interactions
3. **Performance Tests**: For performance-critical changes

#### Running Tests

```bash
# Run all tests
swift test

# Run specific test
swift test --filter DirectoryWatcherTests

# Run with verbose output
swift test --verbose
```

#### Writing Tests

```swift
func testWatcherDetectsFileCreation() throws {
    let tempDir = createTempDirectory()
    let watcher = try DirectoryWatcher(url: tempDir)
    
    let expectation = XCTestExpectation(description: "File creation detected")
    
    watcher.onDirectoryChange = { url in
        XCTAssertEqual(url, tempDir)
        expectation.fulfill()
    }
    
    watcher.start()
    
    // Create test file
    let testFile = tempDir.appendingPathComponent("test.txt")
    try "content".write(to: testFile, atomically: true, encoding: .utf8)
    
    wait(for: [expectation], timeout: 2.0)
}
```

## Documentation

### API Documentation

- All public APIs must have complete documentation
- Include parameter descriptions and return values
- Provide usage examples for complex APIs
- Document error conditions

### README Updates

Update the README.md when adding new features:

- Add to feature list if applicable
- Update code examples
- Add new use cases

### Documentation Files

Maintain documentation in the `docs/` directory:

- `API.md` - Complete API reference
- `Advanced.md` - Advanced usage patterns
- `Performance.md` - Performance optimization

## Submitting Changes

### Pull Request Process

1. **Create a focused PR**: One feature or fix per PR
2. **Write a clear description**: Explain what changes and why
3. **Include tests**: All changes must be tested
4. **Update documentation**: Keep docs in sync with code
5. **Check CI**: Ensure all checks pass

### PR Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing performed

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No new warnings introduced
```

### Code Review Process

1. **Automated checks**: CI must pass
2. **Peer review**: At least one approval required
3. **Maintainer review**: For significant changes
4. **Testing**: Verify tests cover the changes

## Issue Guidelines

### Reporting Bugs

Include the following information:

- macOS/iOS version
- Xcode version
- Swift version
- Minimal reproducible example
- Expected vs actual behavior

### Feature Requests

- Describe the use case
- Explain why it's needed
- Suggest possible implementation approaches
- Consider backwards compatibility

### Bug Report Template

```markdown
**Environment:**
- macOS version: 
- iOS version (if applicable):
- Xcode version:
- FSWatcher version:

**Description:**
A clear description of the bug.

**Reproduction Steps:**
1. 
2. 
3. 

**Expected Behavior:**
What you expected to happen.

**Actual Behavior:**
What actually happened.

**Code Sample:**
```swift
// Minimal code to reproduce the issue
```

**Additional Context:**
Any other relevant information.

```plaintext

## Performance Guidelines

### Performance Testing

- Benchmark before and after changes
- Test with realistic workloads
- Monitor memory usage and CPU utilization
- Test with large directory structures

### Memory Management

- Use `weak` references to avoid retain cycles
- Implement proper cleanup in `deinit`
- Monitor memory leaks with Instruments

### Threading

- Ensure thread safety for all public APIs
- Use appropriate queues for different workloads
- Avoid blocking the main thread

## Security Guidelines

- Never commit secrets or credentials
- Validate all file paths and URLs
- Handle permission errors gracefully
- Follow secure coding practices

## Release Process

### Version Numbering

We follow Semantic Versioning (SemVer):
- **MAJOR**: Breaking changes
- **MINOR**: New features (backwards compatible)
- **PATCH**: Bug fixes

### Release Checklist

- [ ] All tests pass
- [ ] Documentation updated
- [ ] CHANGELOG updated
- [ ] Version bumped
- [ ] Release notes prepared
- [ ] Tag created

## Getting Help

- **GitHub Issues**: For bugs and feature requests
- **Discussions**: For questions and general discussion
- **Documentation**: Check existing docs first
- **Examples**: Look at example code

## Recognition

Contributors will be acknowledged in:
- CHANGELOG.md
- GitHub contributors list
- Release notes (for significant contributions)

Thank you for contributing to FSWatcher! 🎉
