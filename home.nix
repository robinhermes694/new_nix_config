{ inputs, config, pkgs, lib, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  zdotdir = "${config.home.homeDirectory}/.config/zsh";
in

{
  home.username = user;
  home.homeDirectory = if pkgs.stdenv.isDarwin
                       then "/Users/${user}"
                       else "/home/${user}";
  home.stateVersion = "24.11";
  home.packages = with pkgs; [
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # json on the command line
    lazygit
    # the font everything renders in
    nerd-fonts.hack
    tmux
    vim
    neovim
    inputs.herdr.packages.${pkgs.system}.default
  ];
  fonts.fontconfig.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
  # replaces `export PATH=$HOME/.local/bin:$HOME/bin:/usr/local/bin:$PATH`
  #
  # The two nix entries are normally supplied by /etc/profile.d/nix.sh, but on a
  # VM that file is on the boot disk and is deleted whenever
  # the machine is re-assigned, which leaves a fresh shell with no `nix` and
  # none of the packages above. Setting them here keeps them on the home disk.
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/bin"
    "$HOME/.nix-profile/bin"              # packages from home.packages
    "/nix/var/nix/profiles/default/bin"   # the nix CLI itself
    "/usr/local/bin"
  ];

  ###########################################################################
  # zsh -- home-manager owns ~/.config/zsh/.zshrc.
  # Hand-editable, non-nix config lives in ~/.config/zsh/conf.d/*.zsh, which is
  # an out-of-store symlink back into this repo (edit + open a new shell, no
  # rebuild needed).
  ###########################################################################
  programs.zsh = {
    enable = true;
    dotDir = zdotdir;

    autosuggestion.enable = true;      # ghost text from history (was zsh-autosuggestions)
    syntaxHighlighting.enable = true;  # commands turn green when valid
    enableCompletion = true;           # was provided by oh-my-zsh's compinit
    defaultKeymap = "viins";           # was `bindkey -v` + omz vi-mode plugin

    # Ubuntu's /etc/zsh/zshrc runs its own compinit before the one above. Both
    # write ~/.config/zsh/.zcompdump but see a different fpath (the nix
    # site-functions dirs are only added in .zshrc), so each considers the
    # other's dump stale and rebuilds it -- ~0.65s of uncached compdump on every
    # single shell start. Keep only home-manager's compinit.
    envExtra = ''
      skip_global_compinit=1
    '';

    history = {
      size = 100000;
      save = 100000;
      append = true;         # setopt inc_append_history
      share = false;         # setopt nosharehistory
      ignoreDups = true;
      ignoreSpace = true;
      extended = true;
      # NOTE: conf.d/10-history-control.zsh re-points HISTFILE per tmux pane.
      path = "${config.home.homeDirectory}/.zsh_history.d/zsh_history_no_tmux";
    };

    # from the old ~/.aliases plus the handful of oh-my-zsh `git` plugin
    # aliases that are actually worth keeping.
    shellAliases = {
      vi = "nvim";
      vim = "nvim";
      # zsh re-expands the first word of an alias, so `ll`/`la` pick up the
      # colour flag from `ls` below. BSD ls has no --color and reads LSCOLORS
      # rather than LS_COLORS.
      ls = if pkgs.stdenv.isDarwin then "ls -G" else "ls --color=auto";
      ll = "ls -l";
      la = "ls -al";

      g = "git";
      ga = "git add";
      gaa = "git add --all";
      gb = "git branch";
      gbd = "git branch -d";
      gc = "git commit -v";
      "gc!" = "git commit -v --amend";
      gcb = "git checkout -b";
      gck = "git checkout";
      gco = "git checkout";
      gcm = "git checkout $(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')";
      gcmsg = "git commit -m";
      gd = "git diff";
      gds = "git diff --staged";
      gf = "git fetch";
      gfo = "git fetch origin";
      gl = "git pull";
      glo = "git log --oneline --decorate";
      glog = "git log --oneline --decorate --graph";
      gp = "git push";
      gpf = "git push --force-with-lease";
      gpsup = "git push --set-upstream origin $(git branch --show-current)";
      grb = "git rebase";
      grba = "git rebase --abort";
      grbc = "git rebase --continue";
      grbi = "git rebase -i";
      grh = "git reset";
      grhh = "git reset --hard";
      gsb = "git status -sb";
      gst = "git status";
      gsta = "git stash push";
      gstp = "git stash pop";
      gsw = "git switch";
    };

    initContent = lib.mkMerge [
      # functions from the old ~/.aliases that take arguments
      (lib.mkOrder 1000 ''
        gmo() { git merge origin/"$1"; }
        gro() { git rebase origin/"$1"; }
      '')

      # load the hand-written drop-ins last so they can override anything above
      (lib.mkOrder 1500 ''
        for _rc in ''${ZDOTDIR:-$HOME}/conf.d/*.zsh(N); do
          source "$_rc"
        done
        unset _rc
      '')
    ];
  };

  ###########################################################################
  # starship -- replaces powerlevel10k. Mirrors the p10k "lean" config:
  # left  = dir (blue) + git branch/status + prompt char
  # right = command duration (>3s, yellow) + POPPY_WORKSPACE segment
  ###########################################################################
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_state$git_status$character";
      right_format = "$cmd_duration$status$jobs$nix_shell$conda\${env_var.POPPY_WORKSPACE}";

      # starship drops any module that outruns this, silently. The default
      # 500ms is under what git_status costs in a big repo, so the prompt there showed a branch but never a status. 2000
      # clears the ~1.5s a cold untracked cache takes; it is only a ceiling, so
      # small repos are unaffected (dotfiles computes in 3ms).
      command_timeout = 2000;

      # p10k: prompt_char, ❯ insert / ❮ normal, green ok / red error
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
        vimcmd_symbol = "[❮](green)";
        vimcmd_visual_symbol = "[V](yellow)";
        vimcmd_replace_symbol = "[▶](red)";
      };

      # p10k: dir, fg 4 (blue), truncate_to_last, max length 80
      directory = {
        style = "blue";
        truncation_length = 4;
        truncate_to_repo = true;
        truncation_symbol = "…/";
        read_only = " ";
        format = "[$path]($style)[$read_only]($read_only_style) ";
      };

      # p10k: vcs, git backend only, clean=green / dirty=yellow
      git_branch = {
        style = "green";
        symbol = " ";
        truncation_length = 32;
        format = "[$symbol$branch]($style) ";
      };
      git_status = {
        style = "yellow";
        format = "([$all_status$ahead_behind]($style) )";
        # Shell out to git instead of using starship's built-in gitoxide
        # backend. gitoxide ignores git's untracked cache, so it costs ~1s in
        # a big repo no matter what; the git binary reads the cache and
        # comes in at ~0.5s. It also collapses untracked directories the way
        # `git status` does, so counts match (?1 for media/, not ?15).
        # Needs core.untrackedCache=true on the repo to be worth it.
        use_git_executable = true;
        conflicted = "~$count";
        ahead = "⇡$count";
        behind = "⇣$count";
        diverged = "⇡$ahead_count⇣$behind_count";
        untracked = "?$count";
        stashed = "*$count";
        modified = "!$count";
        staged = "+$count";
        renamed = "»$count";
        deleted = "−$count";
      };
      git_state.format = "\\([$state( $progress_current/$progress_total)]($style)\\) ";

      # p10k: command_execution_time, threshold 3s, fg 3 (yellow)
      cmd_duration = {
        min_time = 3000;
        style = "yellow";
        format = "[$duration]($style) ";
      };

      # p10k: status, hidden on success, ✘ in red
      status = {
        disabled = false;
        symbol = "✘";
        style = "red";
        format = "[$symbol$status]($style) ";
      };

      # p10k: background_jobs, fg 1
      jobs = {
        style = "red";
        symbol = "✦";
        format = "[$symbol$number]($style) ";
      };

      nix_shell.format = "[$symbol$state]($style) ";
      conda.format = "[$symbol$environment]($style) ";

    };
  };

  # oh-my-zsh's theme-and-appearance.zsh used to export LS_COLORS; without it
  # `ls --color` falls back to a bare built-in palette. This writes ~/.dir_colors
  # and evals it into the shell (order 550, before the aliases above).
  programs.dircolors = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";

  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";

  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";

  home.file.".config/zsh/conf.d".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/zsh/conf.d";
}
