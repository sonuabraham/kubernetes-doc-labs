# Extend kubectl with plugins – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/extend-kubectl/kubectl-plugins/

> Local only (kubectl v1.35; the cluster is not needed). Instead of `sudo mv … /usr/local/bin`, [make-plugins.sh](make-plugins.sh)
> (not from the docs) builds every plugin of the page in `./plugins` and `./moreplugins` (gitignored); put them first on `PATH` for the
> session. File: [kubectl-foo](kubectl-foo) (the docs' example plugin, **verbatim**).
>
> **Found:**
> 1. `kubectl plugin list` warns `kubectl-create-something overwrites existing command: "kubectl create"`, although the page says `create`
>    plugins are allowed, and `kubectl create something` **does** run the plugin. The warning is misleading for `create`.
> 2. "The first argument that is passed to a plugin will always be the full path": that's `$0` (as the page's parenthesis says), not `$1`.
>    `$1` is the user's first argument.
> 3. Global kubectl flags must come **after** the plugin name: `kubectl -n kube-system foo` → `Error: flags cannot be placed before plugin name: -n`.
>    After it, the plugin simply receives them (`kubectl foo -n x`) and must parse them itself.
> 4. The header now reads `The following compatible plugins are available:` (page: "kubectl-compatible").

## Key ideas (read first)

| Rule | Meaning |
|---|---|
| Name | executable `kubectl-<cmd>[-<sub>…]` on `PATH`; `_` in the file name = `-` (or `_`) on the command line |
| Lookup | the **longest** matching file name wins; the rest of the words become arguments |
| Can't override | built-in commands (`kubectl-version`) and sub-commands of built-ins (`kubectl-attach-vm`), except new `create` sub-commands |
| Same name twice | the first on `PATH` wins; later ones are "overshadowed" |
| Environment | inherited from kubectl (e.g. `KUBECONFIG`); no extra plugin variables |

---

## Lab 1 – Install and list (docs)
```bash
cd tasks/extend-kubectl/kubectl-plugins
./make-plugins.sh
export PATH=$PWD/plugins:$PWD/moreplugins:$PATH
kubectl plugin list
#   The following compatible plugins are available:
#   ./plugins/kubectl-attach-vm
#     - warning: kubectl-attach-vm overwrites existing command: "kubectl attach"
#   ./plugins/kubectl-create-something
#     - warning: kubectl-create-something overwrites existing command: "kubectl create"        <- Found #1
#   ./plugins/kubectl-foo  ./plugins/kubectl-foo-bar  ./plugins/kubectl-foo-bar-baz  ./plugins/kubectl-foo_bar
#   ./plugins/kubectl-invalid
#     - warning: ./plugins/kubectl-invalid identified as a kubectl plugin, but it is not executable
#   ./plugins/kubectl-version
#     - warning: kubectl-version overwrites existing command: "kubectl version"
#   ./moreplugins/kubectl-foo
#     - warning: ./moreplugins/kubectl-foo is overshadowed by a similarly named plugin: ./plugins/kubectl-foo
#   error: 5 plugin warnings were found
```

## Lab 2 – Calling plugins (docs)
| Command | Output |
|---|---|
| `kubectl foo` | `I am a plugin named kubectl-foo` |
| `kubectl foo version` | `1.0.0` |
| `KUBECONFIG=/etc/kube/config kubectl foo config` | `/etc/kube/config` (empty when `KUBECONFIG` isn't set) |
| `kubectl foo bar baz arg1 --meaningless-flag=true` | `My first command-line argument was arg1` |
| `kubectl foo bar baz buz` | `My first command-line argument was buz` (kubectl-foo-bar-baz) |
| `kubectl foo bar buz` | `Plugin kubectl-foo-bar is executed, args: [buz]` |
| `kubectl foo bar` | `Plugin kubectl-foo-bar is executed, args: []` (longest name wins over kubectl-foo) |
| `kubectl foo-bar` / `kubectl foo_bar` | `I am a plugin with a dash in my name` (file `kubectl-foo_bar`) |
| `kubectl create something --x=1` | `my create plugin, args: [--x=1]` |
| `kubectl version` | the built-in (`Client Version: v1.35.10`), never the plugin |
| `kubectl attach vm` | the built-in: `Error from server (NotFound): pods "vm" not found` |
| `kubectl whoami0 hello` | `dollar0=./plugins/kubectl-whoami0 dollar1=hello` (Found #2) |
| `kubectl -n kube-system foo` | `Error: flags cannot be placed before plugin name: -n` (Found #3) |

## Cleanup
```bash
./cleanup.sh                      # removes plugins/ and moreplugins/; start a new shell to drop them from PATH
```
