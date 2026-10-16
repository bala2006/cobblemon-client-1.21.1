# Cobblemon client files - Minecraft 1.21.1 (Fabric)

One-click installer for the exact client files needed to play on the Cobblemon server.

Instead of committing 140 MB of third-party jars, this repo stores a **pinned manifest**
(`mods.json`) and an installer that downloads each file from its **official Modrinth CDN
page** and verifies its **SHA-512** before placing it. What you get is guaranteed to be
byte-identical to the versions the server runs on, and nothing is rehosted.

| File | Version | Needed? | Why |
|---|---|---|---|
| [Cobblemon](https://modrinth.com/mod/cobblemon) | 1.8.2+1.21.1 | **required** | The Pokemon mod itself |
| [Fabric API](https://modrinth.com/mod/fabric-api) | 0.116.17+1.21.1 | **required** | Required by Cobblemon |
| [Sodium](https://modrinth.com/mod/sodium) | 0.6.13 | optional | Large FPS boost; required by Iris |
| [Iris](https://modrinth.com/mod/iris) | 1.8.8 | optional | Shader support |
| [Complementary Reimagined](https://modrinth.com/shader/complementary-reimagined) | r5.9.3 | optional | The shader pack (goes in `shaderpacks/`) |

## Quick start

**You need:** Minecraft **1.21.1** with **Fabric Loader** installed (Java 21 comes with the loader's runtime).

```powershell
git clone https://github.com/bala2006/cobblemon-client-1.21.1.git
cd cobblemon-client-1.21.1
.\install.bat
```

That's it. The script downloads into `%APPDATA%\.minecraft\mods` (and `shaderpacks\`),
verifies every hash, and prints a summary. Wait for the ~140 MB download, then launch
the **Fabric 1.21.1** profile.

No git? Use the green **Code -> Download ZIP** button, unzip, and double-click `install.bat`.

### Command-line options

```powershell
.\install.ps1                 # everything into %APPDATA%\.minecraft
.\install.ps1 -Minimal        # only Cobblemon + Fabric API
.\install.ps1 -Force          # re-download even if files are already correct
.\install.ps1 -Clean          # delete superseded jars (stops duplicate-mod crashes)
.\install.ps1 -GameDir D:\mc  # a different launcher's game folder
```

> If Windows blocks the script, run it once with
> `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1`.

## Enabling shaders

Sodium and Iris only load when the game **starts**, so this menu does not exist until
you restart Minecraft after installing:

**Options -> Video Settings -> Shader Packs -> pick `ComplementaryReimagined_r5.9.3` -> Apply**

Shaders are client-side only - nothing changes for the server or other players. If FPS
drops, lower *Shadow Resolution* and *Shadow Distance* in the shader settings first.

## Pokédex and starter kit

Cobblemon gives you **only the Pokemon** when you pick a starter - no Pokédex, no Poké
Balls, no kit. That is by design. Everything is crafted, or an op can hand it out:

```
/give @s cobblemon:pokedex_red
/give @s cobblemon:poke_ball 20
```

The Pokédex recipe is 5 iron ingots, 2 apricorns, 2 copper ingots and one "screen" item
(a glow ink sac, redstone dust, or glowstone dust works):

```
iron  apricorn  copper
iron  screen   iron
iron  apricorn  copper
```

Poké Balls are 4 red apricorns + 1 copper ingot, which makes 4 of them.

## Joining the server

The server address is **not published in this repo** - it runs in offline ("cracked")
mode, so a public address would let anyone in. Ask for it directly.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Game crashes on startup | You have two copies of a mod. Run `.\install.ps1 -Clean` |
| Shaders menu missing | Fully restart Minecraft; Sodium/Iris load at startup |
| "Missing or unsupported mods" on join | Re-run the installer; your `mods/` must match the manifest |
| Very low FPS | Shaders off first, then lower render distance; Sodium alone should be smooth |
| Download fails | Re-run it - already-verified files are skipped, so it resumes cheaply |
| Wrong game folder | Pass `-GameDir`, e.g. for a custom launcher instance |

Verify a file by hand anytime (certutil ships with Windows and needs no PowerShell modules):

```
certutil -hashfile "%APPDATA%\.minecraft\mods\Cobblemon-fabric-1.8.2+1.21.1.jar" SHA512
# compare with the sha512 in mods.json
```

## Why the jars are not in this repo

- **Size:** the Cobblemon jar alone is **132.86 MB**, and GitHub rejects any file **>= 100 MB**.
  Git LFS would fix that but forces every friend to install git-lfs, and its free tier caps
  bandwidth at 1 GB/month.
- **Licensing:** these are other people's binaries. Sodium (Polyform Shield) and Complementary
  (custom licence) are not meant to be rehosted. Downloading from the official page and
  checking the author-published hash is the standard, correct way to do this.

So this repo ships the *recipe*, not the ingredients, and each file keeps its own licence.

## Maintenance

### Why .NET instead of PowerShell cmdlets

`install.ps1` hashes and downloads with .NET types (`[System.Security.Cryptography.SHA512]`,
`System.Net.WebClient`) instead of `Get-FileHash` / `Invoke-WebRequest`. This is deliberate: if
PowerShell 5.1 inherits a `PSModulePath` that still contains a PowerShell 7 module directory (which
happens when it is launched from `cmd` in a shell that has PowerShell 7 on its path), it autoloads
`Microsoft.PowerShell.Utility` **v7.0.0.0**, which does **not** contain `Get-FileHash`. The script
then dies with `The term 'Get-FileHash' is not recognized`, even though the same script runs fine when
launched from PowerShell directly. .NET types have no such dependency.

To bump a version: edit the entry in `mods.json` (filename, version, size, `sha1`, `sha512`,
`url`) and commit. Everything else is unchanged. `size` and both hashes are checked, so a
typo fails loudly instead of installing a bad file.
