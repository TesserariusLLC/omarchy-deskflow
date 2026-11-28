# Deskflow for Omarchy

Use your Omarchy PC's keyboard and mouse on your other computers (Windows, macOS, Linux) with [Deskflow](https://github.com/deskflow/deskflow). The plugin runs Deskflow without its window and adds:

- **A bar widget** that switches Deskflow on and off and shows which computers are connected. It also switches between saved layouts and gives you the address and TLS fingerprint the other computers need.
- **Guided setup.** Name the computer, then work down a checklist. It covers installing Deskflow, the TLS certificate, the background service, opening the firewall port, NordVPN blocking the LAN, and pairing a new computer by comparing fingerprints. Fixes that need your password open in a terminal.
- **A layout window.** Drag your monitors and the other computers into place, then press Apply. The window writes the Hyprland monitor positions and the matching Deskflow links. A computer can sit against just part of an edge, for example beside one monitor only. Save a layout as a preset and switch back to it from the bar with keys 1–9.
- **Quiet notifications.** You get one notification when a computer connects or disconnects. If the same event repeats, that notification updates and counts up ("LAPTOP disconnected (3)") instead of stacking new ones.
- **Gaming mode.** One switch in the panel for playing games on the other computer, with any layout. See [Gaming mode](#gaming-mode).
- **Optional monitor input switching.** If a monitor is cabled to both computers, a preset can switch its input over DDC/CI and take it out of this computer's layout.

## Screenshots

These use example data: computer names, addresses and monitors are made up.

| Arrange monitors | A preset that hands a monitor to the other computer |
|---|---|
| ![Arrange monitors window with a MacBook left of three monitors](docs/layout.png) | ![The LG monitor shows the MacBook, which sits above the Dell](docs/layout-shared.png) |

| Setup | Bar panel |
|---|---|
| ![Setup checklist with every step done](docs/setup.png) | ![Bar panel with presets, connected computers, address and fingerprint](docs/panel.png) |

> **Omarchy is the server: the computer whose keyboard and mouse you use.** It can't be a client yet, so another computer can't control it. On Wayland, Deskflow's client moves the pointer through the desktop portal's RemoteDesktop interface. Hyprland's portal (`xdg-desktop-portal-hyprland`, 1.4.1 when this was written) doesn't provide that interface, so `deskflow-core client` stops with `No such interface "org.freedesktop.portal.RemoteDesktop"` and then crashes. Hyprland does provide the InputCapture interface, which the server needs, so server mode works. The plugin still offers the client role, but it won't start Deskflow as a client while that interface is missing, so it never crash-loops or fills your notifications. Setup shows the reason instead. When Hyprland adds RemoteDesktop support, client mode will work without changes. Progress: [Deskflow discussion #7499](https://github.com/deskflow/deskflow/discussions/7499).

## Install

```sh
omarchy plugin add https://github.com/TesserariusLLC/omarchy-deskflow.git --enable
```

Click the monitor icon in the bar, then **Set up Deskflow**.

Needs: `deskflow` (setup installs it), `jq`, `openssl`. Optional: `ddcutil` for input switching, `ufw` if you use it.

## Using it

| Where | What |
|---|---|
| Left click | Panel: on/off, layouts, address, fingerprint, start at login |
| Middle click | Switch Deskflow on or off |
| Panel keys | `S` on/off · `G` gaming mode · `A` start at login · `P` layouts · `1`–`9` apply a layout · `L` arrange monitors · `U` setup · `C` copy address · `O` Deskflow's own window |
| Terminal | `omarchy-shell deskflow layout` · `omarchy-shell deskflow setup` |

### Connecting a computer to this one (server)

1. Install Deskflow on the other computer and set it to client mode. Enter the IP shown in the panel. Deskflow adds port 24800 for you. If a computer has more than one network (VPN, virtual machines), use the address on the network both computers share.
2. In **Setup**, click **Pair**, then connect from the other computer.
3. When the fingerprint appears, check it against the one shown on the other computer, then trust it. You only do this once per computer. A computer you've paired before is already trusted and reconnects without asking. Setup lists it under "Connected now".
4. In **Arrange monitors**, add the computer under the exact name it uses and drag it next to the edge you'll cross to reach it.

### Using this computer as a client

Not possible on Hyprland yet; see the note at the top. On a desktop whose portal supports RemoteDesktop: in **Setup**, choose **Client** and enter the server's IP. Then click **Check** to fetch the server's fingerprint, and trust it if it matches what the server shows. The server's own layout decides where this computer sits.

## Layouts and presets

- Deskflow treats each computer as one rectangle: the outline around all of its monitors. Monitors from different computers can't alternate left to right. To get that arrangement, hand the middle monitor to the other computer with input switching.
- A computer's size only changes where along an edge the pointer crosses. If Deskflow logs a computer's size (Debug log level), the window offers it.
- A Hyprland config reload brings every monitor back to its configured position. The plugin then re-applies the active preset's positions, but not its input switching.
Presets are stored in `~/.config/omarchy-deskflow/presets.json`. The plugin points Deskflow at `~/.config/omarchy-deskflow/deskflow-server.conf`.

## Gaming mode

**What it's for.** Turn on **Gaming mode** in the panel (or press `G`) whenever you play a game on the other computer using this computer's keyboard and mouse. It works with whichever layout is active, so you don't need separate gaming presets. Typing, browsing and other everyday use on the other computer don't need it.

**Lock the pointer with Scroll Lock while you play.** Move onto the other computer, then press **Scroll Lock** (ScrLk) on this computer's keyboard. Deskflow then keeps the mouse and keyboard on the other computer until you press Scroll Lock again. Without the lock, a fast flick or a game recentring the mouse can push the pointer over an edge mid-game. From then on your mouse and keys go to this desktop, and the game stops seeing your input. Unlock with Scroll Lock before moving back. Gaming mode and Scroll Lock do different jobs, so use both.

**What can happen if it's off while you play.** Both problems come from how Hyprland hands the keyboard to Deskflow, so they only happen over Deskflow, never with a keyboard plugged into the other computer:

- **The game disconnects you or acts as if you're spamming keys.** Hyprland repeats a held key by sending key-up and key-down about 40 times a second, so the game sees a held movement key as rapid taps. Call of Duty kicks you with "Client command overflow". Other games may stutter or drop input.
- **A key gets stuck, or the keyboard stops working on the other computer.** Each time a keyboard's keymap changes, Hyprland rebuilds the keyboard it hands to Deskflow. A key you're holding at that moment never gets its release, so your character keeps walking until you press that key again on the other computer's own keyboard. Sometimes the other computer stops getting your keystrokes at all while the mouse still works. fcitx5 changes its keymap whenever focus moves on this desktop. A window opening or taking focus here mid-game can set it off, for example a notification, a dialog, or an app that runs its own display like Waydroid.

**What it changes.** While gaming mode is on and Deskflow is running, the plugin turns off key repeat on this desktop and stops fcitx5 (Omarchy's `omarchy-fcitx5` unit). Moving between monitors and computers works as normal. The trade-offs:

- Holding a key types it once instead of repeating, on both computers. For example, holding Backspace deletes one character.
- Shift+CapsLock compose sequences and other fcitx5 input methods, such as Chinese, Japanese or Korean input, don't work.

The plugin restarts Deskflow when gaming mode switches on or off. It also restarts it after any Hyprland config reload, whether gaming mode is on or not. Each of these rebuilds this desktop's keyboard, and Deskflow would otherwise keep using the old one. You'll see the other computer reconnect for a moment. If the pointer reaches the other computer but your typing doesn't, switch Deskflow off and on in the panel.

Turn it off when you're done gaming. Switching Deskflow off also puts key repeat and fcitx5 back. The switch is remembered, so it applies again the next time Deskflow starts, including after a reboot.

## Files it touches

- `~/.config/Deskflow/Deskflow.conf`: role, computer name, server address, links file, certificate path, and `[computer_*]` sections (Deskflow 1.27 only recognises computer names listed there).
- `~/.config/Deskflow/tls/`: certificate, `trusted-clients`, `trusted-servers`.
- `~/.config/systemd/user/omarchy-deskflow.service`: runs `deskflow-core server|client`.
- `~/.config/omarchy-deskflow/` and `~/.local/state/omarchy-deskflow/`.

## Removing it

```sh
~/.config/omarchy/plugins/tesserarius.deskflow/bin/deskflowctl uninstall   # stops and removes the service
omarchy plugin remove tesserarius.deskflow
```

Your Deskflow settings and presets are kept.

## Development

```sh
node tests/layout.test.js        # layout geometry
bin/deskflowctl preset apply <id> --dry-run
```

`bin/deskflowctl` does all the system work. The QML only calls it. See its header for every command.
