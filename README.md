# vim-puppet-nav
A vim plugin for navigating puppet code. It grew out of this two mappings suggested by [TheLocehiliosan](https://github.com/TheLocehiliosan):

```
vnoremap <leader>F "vy:let @v=substitute(@v,'^::','','') \| exec 'Rg '.getreg("v")<cr>
nnoremap <leader>F "vy$:let @v=substitute(@v,'^::','','') \| exec 'Rg '.getreg("v")<cr>
```

Those two mappings are a quick solution to search one's puppet code base for the name of the class pointed to by the cursor, provided the cursor is positioned on the first letter of the class. For example in the code below, the cursor would need to be positioned on the letter `s`:

```
include some::class
```

This plugin takes that idea a bit further by extracting all of the puppet resources in the file (except the built in resources like `file`, `package`, etc) and letting the user define various actions on them:

1. Going directly to the manifest file of a resource. This can be done by either selecting the target resource from an `fzf` driven selection list or extracting the resource from the current line.
2. Going directly to the spec file of a resource.
3. Grepping the code base for a resource
4. Going from the spec file to the manifest of the resource.

In addition, the original `Rg` command from the [fzf.vim](https://github.com/junegunn/fzf.vim) plugin was used as the inspiration for a variant called `Rgp` to grep only the puppet manifests.

# Install
Install using [vim-plug](https://github.com/junegunn/vim-plug) or another vim plugin system. If you don't have a plugin system, put the file in a location that is sourced by Vim such as `~/.vim/plugin`.

# Use
The following functions are exposed for the bindings of your choice:

| Function | Purpose |
| ------------- | ------------- |
| `GoToPuppetManifest()` | Go to the puppet manifest of the resource on the line |
| `SelectResourcesFzf()` | Go to the puppet manifest of the resource selected via an FZF dialog |
| `SearchPuppetCode()` | Search the puppet manifests for the resource on the current line and present the results in an FZF dialog. The result will exclude the current file. The idea is to search for the use of the resource in other manifests.|

The following commands are defined:

| Command | Purpose |
| ------------- | ------------- |
| `Rgp` | Grep the puppet manifests presenting the results using an FZF dialog |

# PuppetDB Integration

The plugin exposes one more function called `PuppetDbLookup()` that will search
PuppetDB for the hosts that use the resource on the current line. Two
pre-requisites need to be satisfied for this to work:

1. PuppetDB is set up and operational.
2. A script called `puppet-resource` is available. The name of the script is
currently hard-coded into the plugin. The script has an `-r` option to specify
the resource type and title. For example:

```bash
# Search for a class named "some_title"
/usr/bin/puppet-resource -r Class%some_title

# Search for a defined type named "some::type" and an instance name of
"instance"
/usr/bin/puppet-resource -r some::type%instance
```

NOTE: I'm not currently providing an implementation of that script for now, but that's something I'm willing to do provided there's interest.

# Dependencies
* [fzf](https://github.com/junegunn/fzf)
* [fzf.vim](https://github.com/junegunn/fzf.vim)
* [Ripgrep](https://github.com/BurntSushi/ripgrep)
* Vim >= 8.1 (because of the "terminal" capability in vim >= 8.1)

# Acknowledgements
* [TheLocehiliosan](https://github.com/TheLocehiliosan) for the initial idea and all the suggestions.
* [Junegunn Choi](https://github.com/junegunn) for the fzf suite of tools. Amazing stuff.
