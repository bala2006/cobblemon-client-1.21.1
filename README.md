# Cobblemon client files — Minecraft 1.21.1 (Fabric)

One-click installer that puts the **exact** client files on your PC so you can join the
Cobblemon server. Works with the normal Minecraft launcher, TLauncher, Prism/MultiMC,
the Modrinth App and CurseForge.

Nothing is re-hosted here. This repo stores a **pinned manifest** (`mods.json`) and an
installer that fetches every file from its **official Modrinth CDN** page and checks the
author-published **SHA-512** before placing it. What you end up with is byte-identical to
what the server runs, and each mod keeps its own licence.

**75 files, 206.6 MB** — 75 mods, one resource pack (Better Leaves), one shader pack
(Complementary Reimagined).

## Requirements

| Thing | Version | Notes |
|---|---|---|
| Minecraft | **1.21.1** | Java Edition, Windows |
| Fabric Loader | **0.20.0** | The installer sets this up for you |
| Java 21 | any | The launcher's bundled runtime is fine |

Fabric Loader **must be 0.20.0** (or at least 0.19.5). Older loaders are the single most
common failure: **Sodium Extra refuses to start below 0.18** and Cobblemon/Bookshelf want
0.17.2+.

## Quick start

```powershell
git clone https://github.com/bala2006/cobblemon-client-1.21.1.git
cd cobblemon-client-1.21.1
.\install.bat
```

No git? Use **Code → Download ZIP**, unzip, and double-click `install.bat`.

Then pick the Fabric profile for 1.21.1 and launch. Wait for the ~207 MB download the first
time; later runs skip files that are already correct.

### Pick the right profile

| Launcher | What to choose |
|---|---|
| **Minecraft launcher** (official) | The installer adds Fabric, so pick the installation named **`fabric-loader-0.20.0-1.21.1`** under *Installations* |
| **TLauncher** | Version box (top-left) → **`fabric-loader-0.20.0-1.21.1`**. The installer also upgrades TLauncher's own *Fabric 1.21.1* entry to 0.20.0 as a fallback |
| **Prism / MultiMC** | Create a **Fabric 1.21.1** instance, set its Fabric version to **0.20.0**, then run `install.bat -GameDir "<instance>\.minecraft"` |
| **Modrinth App** | Create a **Fabric 1.21.1** profile, then `install.bat -GameDir "%APPDATA%\ModrinthApp\profiles\<profile name>"` |
| **CurseForge** | Create a **Fabric 1.21.1** instance with loader 0.20.0, then `install.bat -GameDir "<Instances>\<instance name>"` |

`-GameDir` just needs to be the folder that contains (or will contain) `mods\`.

### Installer switches

```powershell
.\install.ps1                      # auto-detect the game folder: Fabric + all mods
.\install.ps1 -Minimal             # only Cobblemon + Fabric API
.\install.ps1 -Clean               # delete superseded jars (fixes duplicate-mod crashes)
.\install.ps1 -Force               # re-download even if a file is already correct
.\install.ps1 -NoFabric            # do not touch Fabric Loader
.\install.ps1 -KeepMinimapPosition # leave the minimap corner as it is
.\install.ps1 -GameDir D:\mc       # a specific game folder
```

> If Windows blocks the script:
> `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1`

## What gets installed

| Group | Mods |
|---|---|
| **The Pokémon game** | Cobblemon **1.8.2+1.21.1**, Fabric API 0.116.17 |
| **Performance** | Sodium 0.8.13, Lithium, Krypton, FerriteCore, More Culling, Entity Culling¹, Clumps, Let Me Despawn, NetherPortalFix, BadOptimizations |
| **Shaders** | Iris 1.8.14-beta.1, Sodium Extra 0.9.4, Reese's Sodium Options, Sodium Shadowy Path Blocks, Iris Flywheel Compat, Complementary Reimagined **r5.9.3** (the pack itself) |
| **Items & recipes** | JEI, EMI (+ Ores, Enchanting, Professions), Almanac, Crafting Tweaks, Shulker Box Tooltip, Enchantment Descriptions, AppleSkin |
| **Map** | Xaero's Minimap 26.6.0, Xaero's World Map 1.47.0 |
| **Quality of life** | Mod Menu, Better Leaves (resource pack), FancyMenu/Konkrete/Melody, Tips, owo-lib, Balm, Bookshelf, Prickle, OpenLoader, and the rest of the official pack's library set |

¹ Skipped automatically if your launcher ships a skin/cape mod without a fixed id. See below.

## The TLauncher skin/cape conflict (read this if you use TLauncher)

TLauncher injects `tl_skin_cape_*.jar` (mod id `tlskincape`). Two mods in the official
Cobblemon set declare that they *break* that mod:

- **Entity Culling**
- **Not Enough Animations**

Fabric refuses to start when both sides are present, so the installer **keeps your skins and
skips those two mods** and tells you it did. If you would rather have them, delete
`tl_skin_cape*.jar` from `mods\` and run `install.bat` again.

## Minimap position

Xaero's Minimap defaults to the **top left**, which sits under the F3 debug text. The
installer moves it to the **top right** — the same corner the official Cobblemon modpack
ships — by editing `config\xaerohud.txt`:

```
module;id=xaerominimap:minimap;x=0;y=0;centered=false;fromRight=true;fromBottom=false;...
```

Press **Y** in game to move, resize or hide it (that writes the file back in the game's own
format). If Minecraft was running while you installed, it rewrites the file when it closes:
just run `install.bat` once more with the game closed.

## Enabling shaders

Sodium and Iris only load when the game **starts**, so this menu does not exist until you
restart Minecraft after installing:

**Options → Video Settings → Shader Packs → `ComplementaryReimagined_r5.9.3` → Apply**

Shaders are client-side only. If FPS drops, lower *Shadow Resolution* and *Shadow Distance*
first, then turn shaders off entirely — Sodium alone is already smooth.

## On the server

- **No vanilla monsters** — difficulty is *Peaceful*, so no zombies, skeletons, spiders,
  creepers or endermen, and dungeon spawners stay dead. **Pokémon spawning is unaffected**
  (Cobblemon runs its own spawner, completely separate from vanilla mob spawning).
- Passive animals (cows, pigs, sheep, chickens) still spawn, so wool, leather, beds and dye
  are available.
- Cobblemon world generation is on, with the bundled Repurposed Structures datapack
  (Poké Centers in villages). Structures sit close to spawn — the seed was picked for it:
  shaded ruins ~164 blocks, gimmi tower ~192, habitat ~143, plains village ~572.

## Pokédex and starter kit

Cobblemon gives you **only the Pokémon** when you pick a starter — no Pokédex, no Poké
Balls, no gear. That is by design. Everything is crafted, or an op can hand it out:

```
/give @s cobblemon:pokedex_red
/give @s cobblemon:poke_ball 20
```

The Pokédex is 5 iron ingots, 2 apricorns, 2 copper ingots and one screen item (glow ink
sac, redstone dust or glowstone dust):

```
iron  apricorn  copper
iron  screen   iron
iron  apricorn  copper
```

Poké Balls are 4 red apricorns + 1 copper ingot (makes 4). Apricorns grow on apricorn trees
around the world; right-click the tree's apricorn blocks.

## Joining the server

The address is **not published here** — the server runs in offline ("cracked") mode, so a
public address would let anyone in. Ask the owner directly.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Incompatible mods found … Sodium Extra requires 0.18 or later of Fabric Loader … present: 0.17.2` | You launched an old Fabric profile. Re-run `install.bat`, then pick `fabric-loader-0.20.0-1.21.1` |
| `Received N registry entries that are unknown to this client` (bookshelf, jei, xaerominimap, …) | Your client's mods don't match the server. Re-run `install.bat` **and fully restart** Minecraft — mods only load at startup |
| Game crashes on startup | Two versions of one mod. Run `install.ps1 -Clean` |
| `Incompatible mods: … tlskincape` | You added Entity Culling / Not Enough Animations back. Re-run the installer, or delete `tl_skin_cape*.jar` |
| Shaders menu missing | Fully restart Minecraft; Sodium/Iris load at startup |
| Minimap is on the left | The game rewrote the config after you installed. Close the game and run `install.bat` again |
| Very low FPS | Shaders off first, then lower render distance and simulation distance |
| Download fails midway | Re-run it — verified files are skipped, so it resumes cheaply |
| Wrong game folder | Pass `-GameDir`, e.g. for a custom launcher instance |

Check a file by hand any time (certutil ships with Windows and needs no PowerShell modules):

```
certutil -hashfile "%APPDATA%\.minecraft\mods\Cobblemon-fabric-1.8.2+1.21.1.jar" SHA512
# compare with the sha512 in mods.json
```

## Why the jars are not in this repo

- **Size:** the Cobblemon jar alone is **132.9 MB**, and GitHub rejects any file ≥ 100 MB.
  Git LFS would fix that but forces every friend to install git-lfs, and its free tier caps
  bandwidth at 1 GB/month.
- **Licensing:** these are other people's binaries. Sodium (Polyform Shield) and
  Complementary (custom licence) are not meant to be re-hosted. Downloading from the official
  page and checking the author-published hash is the correct way to do this.

So this repo ships the *recipe*, not the ingredients.

## Maintenance

- **Bumping a version:** edit that entry in `mods.json` (filename, version, size, `sha1`,
  `sha512`, `url`) and commit. `size` and both hashes are checked, so a typo fails loudly
  instead of installing a bad file. `mods.json` also carries a `fabric` block (loader,
  installer, MC version) so a version bump is one file.
- **Server parity:** the same manifest drives the server — entries with `"server": true`
  are the ones that go into the server's `mods\` folder (`sync-server-mods.ps1`).
- **Why .NET instead of PowerShell cmdlets:** `install.ps1` hashes and downloads with .NET
  types (`[System.Security.Cryptography.SHA512]`, `System.Net.WebClient`) instead of
  `Get-FileHash` / `Invoke-WebRequest`. If PowerShell 5.1 inherits a `PSModulePath` that
  contains a PowerShell 7 module directory (which happens when it is launched from `cmd` in
  a shell with PowerShell 7 on its path) it autoloads `Microsoft.PowerShell.Utility`
  **v7.0.0.0**, which has no `Get-FileHash`, and the script dies even though it runs fine
  from PowerShell directly. .NET types have no such dependency.
