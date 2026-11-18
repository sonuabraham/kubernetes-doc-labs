#!/usr/bin/env bash
# NOT from the docs: build the page's example plugins in ./plugins and ./moreplugins (instead of sudo mv to /usr/local/bin).
# Use them with:  export PATH=$PWD/plugins:$PWD/moreplugins:$PATH
set -euo pipefail
cd "$(dirname "$0")"; rm -rf plugins moreplugins; mkdir plugins moreplugins
cp kubectl-foo plugins/                                           # the docs' example plugin, verbatim
echo -e '#!/bin/bash\n\necho "My first command-line argument was $1"' > plugins/kubectl-foo-bar-baz      # docs
echo -e '#!/bin/bash\n\necho "I am a plugin with a dash in my name"' > plugins/kubectl-foo_bar             # docs
printf '#!/bin/bash\necho "Plugin kubectl-foo-bar is executed, args: [$*]"\n' > plugins/kubectl-foo-bar  # docs' longest-name section
printf '#!/bin/bash\necho "my create plugin, args: [$*]"\n' > plugins/kubectl-create-something         # docs: create plugins
printf '#!/bin/bash\necho "never runs"\n' > plugins/kubectl-version                                    # docs: limitations
printf '#!/bin/bash\necho "never runs"\n' > plugins/kubectl-attach-vm                                  # docs: limitations
printf '#!/bin/bash\necho "dollar0=$0 dollar1=$1"\n' > plugins/kubectl-whoami0                         # checks the "$0" statement
printf '#!/bin/bash\necho "the moreplugins copy"\n' > moreplugins/kubectl-foo                          # docs: overshadowing
printf '#!/bin/bash\necho x\n' > plugins/kubectl-invalid                                               # docs: not executable
chmod +x plugins/* moreplugins/*; chmod -x plugins/kubectl-invalid
ls plugins moreplugins
