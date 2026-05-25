# Changelog

## [1.0.1] - 25-05-2026
### Added
- Addition of `BSHT_FLAG_LOG_SIMPLE` to help better control script output.
- Addition of `BSHT_FLAG_NO_ROOT` to allow `general::require_root` to be bypassed for scripts that don't need it.

### Fixed
- Bug in `general::format_prompt`, function was not considering the value of `BSHT_FLAG_LOG_SIMPLE`.
- `general::abspath` now returns on success and failure to allow for better error handling in the caller.

## [1.0.0] - 25-03-2026
### Added
- Initial stable release.

### Notes
- This marks the first stable version of the project.
- Prior development occurred in pre-1.0 versions and is not fully documented here.
