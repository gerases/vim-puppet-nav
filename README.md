# vim-puppet-nav
A vim plugin for navigating puppet code. It grew out of this two mappings suggested by [Tim Byrne](https://github.com/TheLocehiliosan):

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
| `PuppetDbTypeTitleLookup()` | See [PuppetDB Integration](#puppetdb-integration).|
| `PuppetDbTypeLookup()` | See [PuppetDB Integration](#puppetdb-integration).|
| `SearchPuppetCode()` | Search the puppet manifests for the resource on the current line and present the results in an FZF dialog. The result will exclude the current file. The idea is to search for the use of the resource in other manifests.|

The following commands are defined:

| Command | Purpose |
| ------------- | ------------- |
| `Rgp` | Grep the puppet manifests presenting the results using an FZF dialog |

# PuppetDB Integration

If the PuppetDB aspect of the plugin is correctly configured, it becomes
possible to see which puppet managed hosts utilize this or that resource.  In
order for puppetdb lookups to work, you need to set the `g:puppetdb_host`
variable to your server in this format: `http(s)://<DBHOST>:<DBPORT>`.

Once the host is set, you can position the cursor on a line with a puppet
resource and execute `:call PuppetDbTypeTitleLookup()` or `:call
PuppetDbTypeLookup()`. The output in a new tab will be a list of hosts using the
resource on the current line.

The difference between those two functions is that given the code below:

```
some::defined::type { 'instance':; }
```

`PuppetDbTypeTitleLookup` will query PuppetDB using both the type (`some::defined::type`) and
the title `instance`, while `PuppetDbTypeLookup` will use only the type.

However given this code:

```
some::class { 'class-name':; }
```

both functions will work identically by using both the type (`class`) and the
title (`class-name`). The reason why title is forcefully used in these cases is
because querying just by the type could potentially produce hundreds of results
and create unnecessary load on PuppetDB.

Example key binding for the functions are below:

```
:nnoremap <Leader>L :call PuppetDbTypeTitleLookup()<cr>
:nnoremap <Leader>l :call PuppetDbTypeLookup()<cr>
```

**NOTE**: Internally, the plugin uses `curl` and`jq` to present the results of the
query. So they should be present on the system.

# Dependencies
* [fzf](https://github.com/junegunn/fzf)
* [fzf.vim](https://github.com/junegunn/fzf.vim)
* [Ripgrep](https://github.com/BurntSushi/ripgrep)
* Vim >= 8.1 (because of the "terminal" capability in vim >= 8.1)
* The following Linux utils: `curl`, `jq`, `column`.

# Acknowledgements
* [Tim Byrne](https://github.com/TheLocehiliosan) for the initial idea and all the suggestions.
* [Junegunn Choi](https://github.com/junegunn) for the fzf suite of tools. Amazing stuff.
