# Changelog

## [0.1.5](https://github.com/jatmn/jatz-distribution/compare/v0.1.4...v0.1.5) (2026-11-08)


### Features

* give destroyed depots and freighters their own wrecks ([#80](https://github.com/jatmn/jatz-distribution/issues/80)) ([c47c78e](https://github.com/jatmn/jatz-distribution/commit/c47c78e4aacb7e0eed02aa7d72be8c86999617a7))
* let logistic robots use provider and buffer depots ([#79](https://github.com/jatmn/jatz-distribution/issues/79)) ([65e2b35](https://github.com/jatmn/jatz-distribution/commit/65e2b356efdea635cd737a90a28b807537230e9c))
* let players set item and fuel depot slots and the fuel depot's tank size ([#78](https://github.com/jatmn/jatz-distribution/issues/78)) ([c90a080](https://github.com/jatmn/jatz-distribution/commit/c90a0800ae1db9b7d26fd20d6b4da5b9fa28afc0))
* road tunnels that freighters drive through under the factory ([#81](https://github.com/jatmn/jatz-distribution/issues/81)) ([19e7e69](https://github.com/jatmn/jatz-distribution/commit/19e7e6954962ab0de22815c772edf10e7bd6bef3))


### Bug Fixes

* cap item depot requests at what their chest holds ([#77](https://github.com/jatmn/jatz-distribution/issues/77)) ([542cdca](https://github.com/jatmn/jatz-distribution/commit/542cdca555431c81fa5b419dc76707112dfadba7))


### Refactoring

* split scripts/logistics.lua into modules, and guard the 200-local limit ([#75](https://github.com/jatmn/jatz-distribution/issues/75)) ([9a20dc3](https://github.com/jatmn/jatz-distribution/commit/9a20dc38657888b347a9c271ab9494b8d7a3b498))

## [0.1.4](https://github.com/jatmn/jatz-distribution/compare/v0.1.3...v0.1.4) (2026-11-08)


### Features

* add a "Full loads only" setting to request and buffer depots ([#68](https://github.com/jatmn/jatz-distribution/issues/68)) ([4c400e4](https://github.com/jatmn/jatz-distribution/commit/4c400e457a0c9ff75c93281ed5d9608dd2259895))
* lower the depots so they hide less of what stands behind them ([#76](https://github.com/jatmn/jatz-distribution/issues/76)) ([6f0c861](https://github.com/jatmn/jatz-distribution/commit/6f0c8619344dbdb0b7a062e259340828f0888ff9))
* run 50% faster on road, as on Transport Drones' road ([#71](https://github.com/jatmn/jatz-distribution/issues/71)) ([2650482](https://github.com/jatmn/jatz-distribution/commit/26504827d208fd0254b841597faee3d9c95969c4))


### Bug Fixes

* cap liquid depot requests at the tank's size ([#74](https://github.com/jatmn/jatz-distribution/issues/74)) ([5c248ca](https://github.com/jatmn/jatz-distribution/commit/5c248cabdaabaf8995969357d218ac9bed77f8ad))
* count pickups already promised against a provider's circuit condition ([#67](https://github.com/jatmn/jatz-distribution/issues/67)) ([82ea6c5](https://github.com/jatmn/jatz-distribution/commit/82ea6c57249f3cbd81148cc88a7efb139fe9a36d))
* give delivering freighters headlights ([#72](https://github.com/jatmn/jatz-distribution/issues/72)) ([bb54422](https://github.com/jatmn/jatz-distribution/commit/bb54422e2a4c7ae11fbfea107f188285322fbf16))
* let blueprint parametrisation change depot requests ([#70](https://github.com/jatmn/jatz-distribution/issues/70)) ([7f35db1](https://github.com/jatmn/jatz-distribution/commit/7f35db12a2a3863faff0cc897a6bd7a9bad34ddf))
* let robots repair freighters, and lose ones killed by a script ([#65](https://github.com/jatmn/jatz-distribution/issues/65)) ([af9e714](https://github.com/jatmn/jatz-distribution/commit/af9e71441d4bc426fb757c523260430a3c572f41))


### CI

* update Pullfrog to v0.1.122 ([#73](https://github.com/jatmn/jatz-distribution/issues/73)) ([7fde38f](https://github.com/jatmn/jatz-distribution/commit/7fde38f2c1d6b2f3ff4618e635592645a8f2c0bc))

## [0.1.3](https://github.com/jatmn/jatz-distribution/compare/v0.1.2...v0.1.3) (2026-11-07)


### Bug Fixes

* keep robot-delivered freighters away from inserters ([#63](https://github.com/jatmn/jatz-distribution/issues/63)) ([a07ecfa](https://github.com/jatmn/jatz-distribution/commit/a07ecfa8522c015b193fe52e10a887ad31d6ee7c))


### CI

* verify portal publication past the portal's CDN cache ([#61](https://github.com/jatmn/jatz-distribution/issues/61)) ([84a4551](https://github.com/jatmn/jatz-distribution/commit/84a45519c6dd80e3a7b5caf1d2ffbd44c7b6e4be))

## [0.1.2](https://github.com/jatmn/jatz-distribution/compare/v0.1.1...v0.1.2) (2026-11-07)


### Features

* let mods declare their items' freighter colors ([#60](https://github.com/jatmn/jatz-distribution/issues/60)) ([77acb6f](https://github.com/jatmn/jatz-distribution/commit/77acb6f87ebe6f9a320e7582113792e976328a0f))


### Bug Fixes

* bring back a depot's settings and freighters when its removal is undone ([#59](https://github.com/jatmn/jatz-distribution/issues/59)) ([bf65413](https://github.com/jatmn/jatz-distribution/commit/bf6541343dbd4f5b9f1d095a23caadf2be478f5f))
* don't crash when a freighter too low on fuel stays home ([#57](https://github.com/jatmn/jatz-distribution/issues/57)) ([eb118d1](https://github.com/jatmn/jatz-distribution/commit/eb118d1ccbc8f35316eb80218f1fc5e29968e88c))

## [0.1.1](https://github.com/jatmn/jatz-distribution/compare/v0.1.0...v0.1.1) (2026-11-06)


### Features

* add a Factorio 2.1 mod thumbnail for the mod browser and portal ([#41](https://github.com/jatmn/jatz-distribution/issues/41)) ([2a3323a](https://github.com/jatmn/jatz-distribution/commit/2a3323ab688759468bfa0fd270fea84e6d1f67df))
* add milestones to the optional Milestones mod ([#43](https://github.com/jatmn/jatz-distribution/issues/43)) ([2aab7d1](https://github.com/jatmn/jatz-distribution/commit/2aab7d17a7e823c25f787b25b4b7a952b9b338b1))
* freighters need fuel and fill up at fuel depots by themselves ([#35](https://github.com/jatmn/jatz-distribution/issues/35)) ([293a193](https://github.com/jatmn/jatz-distribution/commit/293a193facb800ecb086be3c362b27025418b924))
* give every depot, the freighter, road and the monitor a real recipe ([#55](https://github.com/jatmn/jatz-distribution/issues/55)) ([d2ff4e7](https://github.com/jatmn/jatz-distribution/commit/d2ff4e793d28ba9bec3796ed83dfb93c548e0af4))
* let enemies destroy freighters, have freighters run enemies over and pollute ([#33](https://github.com/jatmn/jatz-distribution/issues/33)) ([0a60669](https://github.com/jatmn/jatz-distribution/commit/0a60669b10b3dfbba4df7fa4959adff9aaee09f9))
* let players set the liquid provider and liquid buffer tank sizes ([#27](https://github.com/jatmn/jatz-distribution/issues/27)) ([676e027](https://github.com/jatmn/jatz-distribution/commit/676e027a8ab66b880953945f46cc3d90d4664dcc))
* make freighters pause for one second to load and unload ([#25](https://github.com/jatmn/jatz-distribution/issues/25)) ([fd07ae7](https://github.com/jatmn/jatz-distribution/commit/fd07ae72dee03305a436c8b83e7ce31cf181d9d0))
* make placing freighters as cars a startup setting, off by default ([#38](https://github.com/jatmn/jatz-distribution/issues/38)) ([ff9df22](https://github.com/jatmn/jatz-distribution/commit/ff9df22478e032d247c9136729b754860dc07491))
* mark Transport Drones and its 2.1 forks as incompatible ([#28](https://github.com/jatmn/jatz-distribution/issues/28)) ([e157cec](https://github.com/jatmn/jatz-distribution/commit/e157cec950f95cd5de92ba8fdb4ff4434db095f7))
* paint freighter cargo bays the color of their load ([#29](https://github.com/jatmn/jatz-distribution/issues/29)) ([6d648db](https://github.com/jatmn/jatz-distribution/commit/6d648db19b52a14564a8392b410bd3753207488f))
* show a loaded freighter's cargo icon in alt mode ([#30](https://github.com/jatmn/jatz-distribution/issues/30)) ([c7c1b65](https://github.com/jatmn/jatz-distribution/commit/c7c1b65c8b8b57814b78a9f0f3c15cca8c7baa76))
* switch depots with circuit conditions and read the road network ([#34](https://github.com/jatmn/jatz-distribution/issues/34)) ([e312efc](https://github.com/jatmn/jatz-distribution/commit/e312efc314a8652133d1d696ea06f31e5350d7e3))
* treat Mining Drones' mining depots as item provider depots ([#39](https://github.com/jatmn/jatz-distribution/issues/39)) ([33a078b](https://github.com/jatmn/jatz-distribution/commit/33a078b4b88cfaec59e22c38d0aae631c586eb57))
* unlock the mod by research, with liquid freight, speed and capacity upgrades ([#40](https://github.com/jatmn/jatz-distribution/issues/40)) ([df05b7e](https://github.com/jatmn/jatz-distribution/commit/df05b7ec4d20ac4d5cbe4b0d348b1448f62c8a43))


### Bug Fixes

* allow only belts, pipes and train tracks on road ([#32](https://github.com/jatmn/jatz-distribution/issues/32)) ([3267fc0](https://github.com/jatmn/jatz-distribution/commit/3267fc0fa2276c2e689dbea27ba3641c07175ed9))
* fall back to buffer depots when no provider can supply a request ([#26](https://github.com/jatmn/jatz-distribution/issues/26)) ([a69595d](https://github.com/jatmn/jatz-distribution/commit/a69595d19daece8eb9c443e7a519fa8cef9b03b9))
* index depots by surface and role, and file what freighters bring ([#53](https://github.com/jatmn/jatz-distribution/issues/53)) ([8fda217](https://github.com/jatmn/jatz-distribution/commit/8fda2175142389c0f3857276ebc3b86ed08b18fc))
* let freighters swerve through junctions instead of sliding sideways ([#54](https://github.com/jatmn/jatz-distribution/issues/54)) ([ab64161](https://github.com/jatmn/jatz-distribution/commit/ab641616f23f1942661426b43e638b636a77bfa0))
* make less garbage and fewer engine objects per tick, so collections stall less ([#50](https://github.com/jatmn/jatz-distribution/issues/50)) ([226010f](https://github.com/jatmn/jatz-distribution/commit/226010f780e52ea1810d29d03c23107ab635c7fc))
* make mod setting tooltips easier to read ([#42](https://github.com/jatmn/jatz-distribution/issues/42)) ([d0caa8f](https://github.com/jatmn/jatz-distribution/commit/d0caa8f67ed5aced8e79c8de448ced3aa775b249))
* slow delivering freighters to Transport Drones' default speed ([#31](https://github.com/jatmn/jatz-distribution/issues/31)) ([097a83b](https://github.com/jatmn/jatz-distribution/commit/097a83b92205e2a727688d74af53c8bc0d8eaa20))
* spread depot and freighter checks over the second ([#49](https://github.com/jatmn/jatz-distribution/issues/49)) ([e207e78](https://github.com/jatmn/jatz-distribution/commit/e207e7879cfcb8abc7ee7e5434cd310dd8db558d))


### Documentation

* make the README friendlier for players, with a separate player guide ([#20](https://github.com/jatmn/jatz-distribution/issues/20)) ([0f2174f](https://github.com/jatmn/jatz-distribution/commit/0f2174f64eeb9b7a49d28cfda29cb7b16cec47eb))


### Tests

* benchmark UPS against Transport Drones and require it for mod changes ([#36](https://github.com/jatmn/jatz-distribution/issues/36)) ([9149b1c](https://github.com/jatmn/jatz-distribution/commit/9149b1c6376ee4b061f3745ac466ffe46e59cf77))


### CI

* install Lua without apt and cancel superseded CodeQL scans ([#45](https://github.com/jatmn/jatz-distribution/issues/45)) ([e54e75d](https://github.com/jatmn/jatz-distribution/commit/e54e75d0ce7ee5734cc8be157379c24c983451f0))
* keep the Mod Portal page in portal/ and sync it on release ([#56](https://github.com/jatmn/jatz-distribution/issues/56)) ([32357c6](https://github.com/jatmn/jatz-distribution/commit/32357c60a26166b789f3355d875da054dbe11ee3))
* prepare public development and release automation ([#19](https://github.com/jatmn/jatz-distribution/issues/19)) ([bc576e1](https://github.com/jatmn/jatz-distribution/commit/bc576e1c53c5e9c65cebdf2a21b53fe25c89dff0))
* run CodeQL with the security-and-quality queries ([#44](https://github.com/jatmn/jatz-distribution/issues/44)) ([4c4152a](https://github.com/jatmn/jatz-distribution/commit/4c4152aaa3287d244f9cca581e2f655a8cce597b))
* skip the package check on Release Please's unfinalized commit ([#52](https://github.com/jatmn/jatz-distribution/issues/52)) ([23cded9](https://github.com/jatmn/jatz-distribution/commit/23cded92e05f8c10ebc4a2af8f9ebe6b2fe209b3))
