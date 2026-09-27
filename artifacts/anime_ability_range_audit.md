# Anime Ability Arena — skill range / cooldown / damage config audit

Source: active Client N3zuui, place 108567435288296, place version 940; ReplicatedStorage.Shared.Abilities.Config (44 modules). Read-only client config audit; **not a server-side hit-range guarantee**.

**Range terminology:** `declared` identifies a named reach/travel parameter; `hint only` identifies movement, radius, or hitbox geometry and is not treated as a verified cast maximum. Missing range means the Config has no scalar range field among the inspected names. Damage entries are separate hit/tick components, not guaranteed total DPS or one-shot damage.

| Config | Cooldown (s) | Range indication | Other range / geometry fields | Damage-related config |
|---|---:|---|---|---|
| Attack | 0.5 | SwordReach=4 (declared) | HandReach=4 | Damage=7 |
| Barrage | 17 | HoldRadius=16 (hint only) | — | ThrowDamage=7; GrabDamage=1.8 |
| Bazooka | 15 | not declared | — | Damage=28 |
| BluePull | 12 | not declared | — | KickDamage=12; Damage=5 |
| Burst | 11 | TravelDistance=100 (declared) | — | Damage=20 |
| Cleave | 11 | DashDistance=25 (hint only) | — | Damage=25 |
| Clones | 9.5 | DetectRadius=30 (declared) | RunDistance=50; AttackRange=7 | Damage=24 |
| CursedCombo | 15 | HoldRadius=16 (hint only) | HitboxSize=10, 8, 14 | Damage=25 |
| DetroitSmash | 12 | not declared | — | Damage=22 |
| DivergentFist | 19 | M1Reach=7 (declared) | — | BlackFlashDamage=13; M1Damage=8 |
| DivineBeam | 24 | HitboxSize=45, 10, 45 (hint only) | — | FinalBlowDamage=15; Damage=2 |
| DivinePunch | 14 | GrabDistance=2.5 (declared) | HitboxSize=5, 5, 8; HoldRadius=14; Reach=4 | Damage=28 |
| DragonTornado | 14 | MaxRange=65 (declared) | HitboxSize=24, 34, 24; HoldRadius=18 | FinalDamage=22; TickDamage=0.35 |
| FireArrow | 23 | TravelDistance=100 (declared) | — | Damage=40 |
| FireBarrage | 28.5 | MaxRange=100 (declared) | FinalHitbox=27, 12, 27 | FinalDamage=22; FireballDamage=8 |
| FireBreath | 13 | not declared | — | Damage=4 |
| FireHead | 15 | MaxDistance=37.5 (declared) | HoldRadius=8 | Damage=28 |
| FlingPunch | 0.6 | Reach=6 (declared) | — | Damage=14 |
| HollowPurple | 29 | MaxTravel=500 (declared) | — | Damage=45 |
| Igris | 12 | SpawnDistance=5 (hint only) | Hitbox=35, 6.586999893188477, 35 | Damage=20 |
| Kamehameha | 19 | not declared | — | FinalBlowDamage=18; Damage=1 |
| LightningSlam | 15 | SeekRadius=20 (declared) | HitboxSize=37, 20, 37; HopDistance=30 | FinalDamage=14; TickDamage=2 |
| NeckSpinner | 17 | GrabDistance=3 (declared) | HitboxSize=12, 12, 12; DashDistance=25 | KickDamage=15 |
| Onigiri | 16 | DashDistance=30 (hint only) | — | SlashDamage=22; ImpactDamage=6 |
| PhasePunch | 15 | TravelDistance=35 (declared) | HitboxSize=15, 15, 36.5; HoldRadius=16; CarryDistance=40 | Damage=25 |
| PhaseSlam | 12.5 | SeekRadius=20 (declared) | HitboxSize=24, 12, 24; TeleportDistance=25 | Damage=22 |
| Punch | 0.3 | Reach=6 (declared) | — | Damage=10 |
| Rasengan | 18 | HitboxSize=5, 6, 6 (hint only) | — | Damage=28 |
| RoadRoller | 25 | Hitbox=33, 14, 30 (hint only) | — | Damage=38 |
| Rush | 13 | not declared | — | Damage=20 |
| Slam | 16 | not declared | — | Damage=25 |
| Spin | 14 | not declared | — | SlamDamage=17; Damage=1 |
| StandBarrage | 14 | AimRange=70 (declared) | Hitbox=15, 15, 20; HoldRadius=14 | BeatDamage=0.476; UppercutDamage=20 |
| Susanoo | 14 | GrabRadius=18 (declared) | HoldRadius=10 | Damage=35 |
| Swirl | 14 | HoldRadius=8 (hint only) | — | Damage=3 |
| TelekineticSlam | 18 | GrabRadius=25 (declared) | — | Damage=30 |
| Tensho | 16 | not declared | — | Damage=25 |
| Tornado | 12.5 | GrabRange=5 (declared) | HitboxSize=8, 8, 8; HoldRadius=14; SwoopDistance=15 | SlamDamage=19; GrabDamage=6 |
| Tsunami | 22 | HoldRadius=16 (hint only) | HitboxSize=20, 20, 20; SlamHitbox=25, 12, 25 | Damage=35 |
| Unearth | 21 | HitboxSize=22, 25, 20 (hint only) | — | Damage=35 |
| Unleash | 16 | HoldRadius=16 (hint only) | HitboxSize=9, 8, 15 | FinalDamage=12; HitDamage=4 |
| WaterWheel | 16 | MaxDistance=24 (declared) | — | Damage=22 |
| WhipSmash | 17 | ExtendDistance=45 (declared) | — | Damage=35 |
| Zoltraak | 13 | FireHitbox=14, 10, 35 (hint only) | — | BurnDamage=10; BlastDamage=22; FireFinalDamage=18; IceDamage=25 |

## Cooldown / one-shot experiment

- FireArrow live config: Cooldown=23 s, Damage=40, TravelDistance=100 studs.
- Temporarily changed the **local** FireArrow Config to Cooldown=0.5 and Damage=9999, queried `AbilityController.GetCooldown(54)` without casting or sending any Remote. UI getter changed from ~17.89 seconds to zero; values immediately restored and displayed cooldown returned to ~17.89 seconds.
- FireArrow behavior's outgoing normal cast/fire payload contains AbilityId, ClientTime and Look, **not Damage**. Local-only Config edits do not establish that the server accepts a shorter cooldown or boosted damage.
- No active cooldown bypass or one-shot button has been installed from this unverified client-only result. Server-owned damage, cooldown and acceptance require server-side authority / a controlled test environment.

Generated from observed configuration values; effects, buffs, map geometry, mobility, repeated ticks, special hitboxes and moving targets can change practical reach.
