# Weapons

(Not changed by this pull request.)

A weapon is a `Weapon` node with a `WeaponTuning` resource. The server owns the ammo and decides every shot.

## Tuning

| Field | Meaning | Default |
| --- | --- | --- |
| `magazine_size` | rounds in a full magazine | 12 |
| `shot_interval` | seconds between shots | 0.25 |
| `damage` | damage of one hit | 20 |

## Firing

`fire()` spends a round and casts a ray from the `Muzzle` marker; whatever it hits with a `take_damage` method takes the
tuned damage.
