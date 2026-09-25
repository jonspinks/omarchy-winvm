# Windows VM — an Omarchy bar widget

An icon that exists only while the Omarchy Windows VM (`omarchy-windows-vm`)
is running. Click it for what the VM is costing the host and the controls to
get back to it or shut it down.

## Install

```bash
omarchy plugin add https://github.com/jonspinks/omarchy-winvm --enable
```

`--enable` places it in the bar; `omarchy plugin enable blacksheep.winvm --before omarchy.agents`
puts it somewhere specific. It stays hidden until the VM is running.

## Interactions

| Gesture | What happens |
|---|---|
| hover | state, CPU, memory, disk and network rates |
| left click | panel |
| right click | focus the RDP window, or open one |
| `c` | Connect / Focus |
| `w` | web console at `http://127.0.0.1:8006` (useful while Windows is still booting and RDP isn't up) |
| `f` | open `~/Windows`, the folder the guest sees as a network share |
| `s`, twice | shut the VM down |
| `r` | resample now |

**Connect** doesn't go through `omarchy-windows-vm launch`, because on a VM
that's already running that re-runs the privileged bring-up and asks for a
password just to reconnect. `bin/winvm-connect` starts `xfreerdp3` itself,
using the credentials the installer saved in `~/.config/windows/credentials`
and the same flags as the launcher. Closing a window opened this way leaves
the VM running.

**Stop** asks for your password once. If the original `launch` is still
waiting on its RDP window, `bin/winvm-stop` closes that window and lets the
launcher stop the VM, as it would anyway. Stopping the container directly
would make the launcher ask for a password a second time. Docker's SIGTERM
becomes an ACPI shutdown in the guest, so Windows gets to shut down cleanly.

## The numbers

`bin/winvm-sample` reads everything without privileges. It doesn't need the
docker group, so the widget never prompts for a password:

| Figure | Source |
|---|---|
| detection | a `docker-*.scope` cgroup holding a `qemu-system-*` process named `windows` |
| CPU | cgroup `cpu.stat`, against the guest's vCPUs (from qemu's `-smp`) and against the host |
| Memory | cgroup `memory.current`, against the guest's `-m` |
| Disk I/O | cgroup `io.stat`, the busiest single device (dm-crypt and the NVMe under it report the same bytes) |
| Network | `eth0` in the qemu process's network namespace |
| Image | allocated blocks of the sparse `~/.windows/data.img` |

Memory is the host's view. Windows zeroes its RAM at boot, so a running guest
holds nearly all of its allocation whatever Task Manager says. The meter shows
what the VM takes from Linux, not how much Windows is using.

One sample is a single ~30ms fork. The widget polls every 5s while closed
(which is also how quickly the icon appears after the VM starts) and every 2s
while the panel is open. Both are settable inline in `shell.json`:

```json
{ "id": "blacksheep.winvm", "interval": 2, "idleInterval": 5 }
```

## License

MIT
