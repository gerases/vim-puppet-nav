function! Debug(message)
  if exists('g:puppet_nav_debug') && g:puppet_nav_debug == 1
    echom "DEBUG:".a:message
  endif
endfunction

function! ExtractTypeName(line)
  " Return either the name of a class or the name of a defined type

 " The rules below are:
 "
 " 1. class/define definition at the top of a manifest
 " 2. e.g. class { 'some::class': }.
 " 3. e.g. some::define { 'instance': }.
 " 4. an include/contain statement

  let l:current_dir = getcwd()
  if stridx(l:current_dir, expand('~/proj/puppet')) == -1
    echo "Not in the proj puppet directory"
    return ''
  endif

  let l:patterns = [
        \ '^\(class\|define\)\s\+\zs[^ ({]\+',
        \ '^[^#]\s*class\s*{\s*[''"]\zs[^''"]\+\ze',
        \ '^[^#]\s*\zs[a-zA-Z0-9_:]\+\ze\s*{\s*.*:',
        \ '\(include\|contain\)\s\+\zs\S\+',
        \ ]

  " Find the first matching pattern
  for l:pattern in l:patterns
    let l:match = matchstr(a:line, l:pattern)
    if l:match != ''
      call Debug("Matched '".l:match. "' with pattern: '".l:pattern."'")
      return l:match
    endif
  endfor
  echo "Couldn't find a class or defined type on the current line."
  return ''
endfunction

function! SearchPuppetCode(line)
  let l:type_name = ExtractTypeName(a:line)
  call Debug("The type name is:[start]".l:type_name."[end]")
  if l:type_name == ''
    return ''
  endif

  " Find instances of the class name or defined type in the repo. The cases are:
  "
  " 1. Class or define definition
  "   Ex: class { 'some::class'
  "   Ex: define { 'some::define'
  " 2. Class resource-like instantiation
  "   Ex: class { 'some::class':}
  " 3. Defined type instantiation
  "   Ex: some::define { '
  " 4. Class include
  "   Ex: include some::class

  " NOTE: The pattern should be in the language of ripgrep not vim!
  let l:patterns = []
  call add(l:patterns, '(?:^class|^define)\s+'.type_name.'[^:]')
  call add(l:patterns, '^[^#]\s+class\s*\{\s*(["''])'.type_name.'\1')
  call add(l:patterns, '^[^#]\s+'.type_name.'\s*\{\s*.*:')
  call add(l:patterns, '(include|contain)\s+'.type_name.'[^:]')
  let l:pattern = '(?:' . join(l:patterns, '|') . ')'
  call Debug("The pattern is:".l:pattern)
  call RgPuppet(l:pattern, ["-g'!".expand('%')."'"])
endfunction

function! GoToPuppetManifest(line)
  let l:type_name = ExtractTypeName(a:line)
  if l:type_name == ''
    return ''
  endif

  let module_path = substitute(type_name, '::', '/', 'g')

  if stridx(module_path, '/') == -1
    " Insert 'manifests' after the module name
    let manifest_path = module_path."/manifests/init"
  else
    " Insert 'manifests' after the module name
    " call Debug(module_path)
    let manifest_path = substitute(module_path, '\v^([^/]+)', '\1/manifests', '')
  endif

  " Add the ".pp" extension to form the manifest path
  let manifest_file = findfile(manifest_path . '.pp', 'modules/;')

  " If the manifest is found, open it in a new tab
  if !empty(manifest_file)
      execute 'tabedit' manifest_file
  else
      echo "Manifest not found: " . manifest_path . ".pp"
  endif
endfunction

function! RgPuppet(pattern, additional_opts=[])
  " Find instances of the class in the puppet code
  let l:cmd_list = [
        \ 'rg',
        \ '--pcre2',
        \ '--column',
        \ '--line-number',
        \ '--no-heading',
        \ '--color=always',
        \ '-g',
        \ shellescape('*.pp', 1),
        \ shellescape(a:pattern, 1),
        \ ]

  " Append additional options if provided
  if !empty(a:additional_opts)
    let l:cmd_list += a:additional_opts
  endif

  " Join the list into a single command string
  let l:cmd = join(l:cmd_list, ' ')
  call Debug("cmd:[start]".l:cmd."[end]")
  call fzf#vim#grep(l:cmd, fzf#vim#with_preview())
endfunction
