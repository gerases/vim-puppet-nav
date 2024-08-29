function! Debug(message)
  if exists('g:puppet_nav_debug') && g:puppet_nav_debug == 1
    echom "DEBUG:".a:message
  endif
endfunction

function! s:Ensure_Proj_Dir()
  let l:current_dir = getcwd()
  if stridx(l:current_dir, expand('~/proj/puppet')) == -1
    echo "Not in the proj puppet directory"
    return 0
  endif
  return 1
endfunction

function! Select_Items_Fzf()
  if s:Ensure_Proj_Dir() == 0
    return
  endif

  let l:allowed_ftypes = ["puppet", "ruby"]
  if index(l:allowed_ftypes, &filetype) == -1
    echo "Not a puppet or spec file"
    return
  end

  let items = CollectMatches()
  if len(items) == 0
    echo "Nothing found"
    return
  end

  let options = {
      \ 'options': ['--prompt', 'Resource> '],
      \ 'source': items,
      \ 'window' : { 'height': '20%', 'width': 40 },
      \ 'sink': function('Fzf_Sink'),
      \ }
  call fzf#run(fzf#wrap(options))
endfunction

function! CollectMatches()
    let matches = []
    " Loop over all lines in the buffer
    for line_num in range(1, line('$'))
        let line = getline(line_num)
        let l:match = ExtractTypeName(line)
        if l:match == ''
          continue
        endif
        call add(matches, l:match)
    endfor
    return sort(uniq(matches))
endfunction

function! ExtractTypeName(line=getline('.'))
  " Return either the name of a class or the name of a defined type

 " The rules below are:
 "
 " 1. class/define definition at the top of a manifest
 " 2. e.g. class { 'some::class': }.
 " 3. e.g. some::define { 'instance': }.
 " 4. an include/contain statement
 " 5. a describe statement in a spec file

  if s:Ensure_Proj_Dir() == 0
    return
  endif

  let l:patterns = [
        \ '^\(class\|define\)\s\+\zs[^ ({]\+',
        \ '^[^#]\s*class\s*{\s*[''"]\zs[^''"]\+\ze',
        \ '^[^#]\s*\zs[a-zA-Z0-9_:]\+\ze\s*{\s*.*:',
        \ '^[^#]\s*\(include\|contain\)\s\+\zs[a-zA-Z0-9_:]\+',
        \ '^describe\s*[''"]\zs[^''"]\+\ze',
        \ ]

  let l:ignore = [
        \ 'exec',
        \ 'file',
        \ 'group',
        \ 'it',
        \ 'notify',
        \ 'package',
        \ 'schedule',
        \ 'service',
        \ 'tidy',
        \ 'user',
        \]

  " Find the first matching pattern
  for l:pattern in l:patterns
    let l:match = matchstr(a:line, l:pattern)
    if l:match != ''
      let l:match = substitute(l:match, "^::", "", "")
      " Ignore built in resources
      if index(l:ignore, l:match) != -1
        call Debug("Ignoring '".l:match)
        return
      end
      call Debug("Matched '".l:match. "' with pattern: '".l:pattern."'")
      return l:match
    endif
  endfor
  return ''
endfunction

function! SearchPuppetCode(line=getline('.'))
  let l:type_name = ExtractTypeName(a:line)
  if l:type_name == ''
    echo "Couldn't find a class or defined type on the current line."
  endif

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
  " 5. Class include
  "   Ex: describe statement

  " NOTE: The pattern should be in the language of ripgrep not vim!
  let l:patterns = []
  call add(l:patterns, '(?:^class|^define)\s+'.type_name.'[^:]')
  call add(l:patterns, '^[^#]\s+class\s*\{\s*(["''])'.type_name.'\1')
  call add(l:patterns, '^[^#]\s+'.type_name.'\s*\{\s*.*:')
  call add(l:patterns, '(include|contain)\s+'.type_name.'[^:]')
  call add(l:patterns, '^describe\s*(["''])'.type_name.'\2')
  let l:pattern = '(?:' . join(l:patterns, '|') . ')'
  call Debug("The pattern is:".l:pattern)
  call RgPuppet(l:pattern, ["-g'!".expand('%')."'"])
endfunction

function! Fzf_Sink(line)
  call GoToPuppetManifest(a:line, 0)
endfunction

function! GoToPuppetManifest(line, extract=1)
  if a:extract == 0
    " Meaning 'line' contains the extracted resource name already
    let l:type_name = a:line
  else
    let l:type_name = ExtractTypeName(a:line)
  end

  if l:type_name == ''
    echo "Coudn't extract resource name"
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
      execute '-tabedit' manifest_file
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

command! -nargs=1 Rgp call RgPuppet(<f-args>)
