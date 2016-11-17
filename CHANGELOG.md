#Change Log
This project adheres to [Semantic Versioning](http://semver.org/).

This CHANGELOG follows the format listed at [Keep A Changelog](http://keepachangelog.com/)

## [0.3.0] - 2016-11-17

### Fixed

- #4 - SNMP Trap template values were not getting replaced properly - Thanks @dhassett-tr! #5
- #6 - Fix Travis builds by restricting upper range for certain dependencies

## [0.2.1] - 2016-06-04
### Changed
- Fixing rubocop warnings
- Removed warning about SNMPv1 traps

## [0.2.0] - 2016-06-04
### Added
- README: Instructions on installation

### Fixed
- Log message handling from @amdprophet
- Autodiscovery of sensu-client's JIT event socket
- Better handling when the event socket is missing/unconfigured


### Changed
- README: Reformatting and extended examples
- Reduced the log noise by reducing the log severity on a number of messages



## [0.1.0] - 2016-06-04
### Added
- initial release
