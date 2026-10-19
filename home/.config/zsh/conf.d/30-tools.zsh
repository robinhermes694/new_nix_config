# Third-party tool init that is not managed by nix.
# Everything here probes for the tool first so the same file works on both the
# mac and the ubuntu box.

#### conda ####
# Replaces the hardcoded `conda init` block from the legacy .zshrc.
# starship renders the env itself via its `conda` module, so stop conda from
# prepending `(base) ` to PS1 on activation.
export CONDA_CHANGEPS1=false
# Activating base costs a second python interpreter startup (~0.37s) on every
# shell. `conda activate <env>` still works instantly off the hook below.
export CONDA_AUTO_ACTIVATE_BASE=false
for _conda_root in "$HOME/miniconda3" "$HOME/miniforge3" "$HOME/anaconda3" "/opt/homebrew/Caskroom/miniconda/base"; do
  if [[ -x "$_conda_root/bin/conda" ]]; then
    __conda_setup="$("$_conda_root/bin/conda" shell.zsh hook 2>/dev/null)"
    if [[ $? -eq 0 ]]; then
      eval "$__conda_setup"
    elif [[ -f "$_conda_root/etc/profile.d/conda.sh" ]]; then
      . "$_conda_root/etc/profile.d/conda.sh"
    else
      path=("$_conda_root/bin" $path)
    fi
    unset __conda_setup
    break
  fi
done
unset _conda_root


# Source Nix profile
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi
# End Nix
