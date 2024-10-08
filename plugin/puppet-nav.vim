let g:plugin_dir = expand('<sfile>:p:h')

function ShellEscape(str)
  return system('printf %q ' . a:str)
endfunction

function! Debug(message)
  if exists('g:puppet_nav_debug') && g:puppet_nav_debug == 1
    echom printf("Debug: %s", a:message)
  endif
endfunction

function! s:Call_With_Cd(func, ...)
  if !exists('g:puppet_nav_proj_path')
    throw "The g:puppet_nav_proj_path variable is not set. See https://github.com/gerases/vim-puppet-nav?tab=readme-ov-file#use"
  endif

  let l:cur_dir = getcwd()
  call s:chdir(g:puppet_nav_proj_path)
  let l:result = call(a:func, a:000)
  call s:chdir(l:cur_dir)
  return l:result
endfunction

function! s:chdir(path)
  try
    exe printf('lcd %s', a:path)
  catch
    echoerr printf("An error occurred: %s", v:exception)
  endtry
endfunction

function! SelectResourcesFzf()
  " Call CollectResources to find all resources in the manifest
  " and present the user with an fzf window to select one of them, after
  " which the corresponding manifest will be opened.

  let l:allowed_ftypes = ["puppet", "ruby"]
  if index(l:allowed_ftypes, &filetype) == -1
    echo "Not a puppet or spec file"
    return
  end

  let l:resources = CollectResources()
  if len(l:resources) == 0
    echo "Nothing found"
    return
  end

  let options = {
      \ 'options': ['--prompt', 'Resource> '],
      \ 'source': resources,
      \ 'window' : { 'height': '20%', 'width': 40 },
      \ 'sink': function('FzfSink'),
      \ }
  call fzf#run(fzf#wrap(options))
endfunction

function! QueryPuppetdbAgainstManifest()
  call PuppetDbLookup(FindDefinitionLine())
endfunction

function! FindDefinitionLine()
  " Get the line number on which the definition of the class/define begins
  for line_num in range(1, line('$'))
    let line = getline(line_num)
    if matchstr(line, '\v\s*class|define') != ''
      return line
    endif
  endfor

  echo "Couldn't find the definition line in the manifest"
  return
endfunction

function! GetResourceTitle(resource)
  " Given resource record, which consists of the resource type and title,
  " return the name of the define/class/include/contain/describe _or_
  " the name of a defined type instance.
  if IsDefinedTypeInstance(a:resource)
    " if this is an _instance_ of the defined type
    return a:resource["type"]
  else
    " if this is the definition of a class or a defined type
    return a:resource["title"]
  endif
endfunction

function! CollectResources()
    " Scan the file, find all resources (classes, defined types) and return
    " their titles in a list. For defined types, the defined type name is
    " put into the list instead of its title. This is because ultimately this
    " list is to be shown with fzf so that the user could go to the the
    " definition of the respective resource.
    let l:titles = []
    " Loop over all lines in the buffer
    for line_num in range(1, line('$'))
        let line = getline(line_num)
        let l:resource = ExtractResource(line)
        if l:resource == {}
          continue
        endif
        call add(l:titles, GetResourceTitle(resource))
    endfor
    return sort(uniq(l:titles))
endfunction

function! ExtractResource(line=getline('.'), core_resources=0)
  " Return either the name of a class or the name of a defined type

 " The rules below are:
 "
 " 1. class/define definition at the top of a manifest
 " 2. e.g. class { 'some::class': }.
 " 3. e.g. some::define { 'instance': }.
 " 4. an include/contain statement
 " 5. a describe statement in a spec file

  let l:patterns = [
        \ '^\(class\|define\)\s\+\zs[^ ({]\+',
        \ '^[^#]\s*\(class\)\s*{\s*[''"]\zs[^''"]\+\ze',
        \ '^[^#]\s*\([a-zA-Z0-9_:]\+\)\s*{\s*[''"]\?\zs[^''":]\+\ze[''"]\?:',
        \ '^[^#]\s*\(include\|contain\)\s\+\zs[a-zA-Z0-9_:]\+',
        \ '^\(describe\)\s*[''"]\zs[^''"]\+\ze',
        \ ]

  let l:core_resources = [
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
    " The zeros element contains the match
    " The 1st, 2nd and so contain captured groups
    let l:match = matchlist(a:line, l:pattern)
    if l:match != []
      " Examples of resource_instance:
      "   * identifier after 'class', 'include' or 'contain';
      "   * instance of a defined type;
      let l:resource_instance = substitute(l:match[0], "^::", "", "")
      " Examples of resource_type: 'class', 'include', 'contain', 'local::home'
      let l:resource_type = substitute(l:match[1], "^::", "", "")
      " Ignore built-in resources
      if a:core_resources == 0 && index(l:core_resources, l:resource_type) != -1
        call Debug("Ignoring '".l:resource_type)
        continue
      end
      call Debug(printf("Matched %s with pattern %s", l:resource_type, l:pattern))
      let l:result = {'title': l:resource_instance}
      if index(['class', 'include', 'contain', 'describe'], l:resource_type) != -1
        let l:result['type'] = 'class'
      elseif l:resource_type == 'define'
        let l:result['type'] = 'defined_type'
      else
        let l:result['type'] = l:resource_type
      endif
      return l:result
    endif
  endfor
  return {}
endfunction

function! SearchPuppetCode(line=getline('.'))
  " Given a line of puppet code:
  "   1. Extract the type
  "   2. Look for a mention of that type all of the puppet code (.pp files)
  "      excluding the file where the function was called

  let l:resource = ExtractResource(a:line)
  if empty(l:resource)
    echo "Couldn't find a class or defined type on the current line."
    return
  endif

  let l:type = GetResourceTitle(resource)

  call Debug(printf("The type name is:[start]%s[end]", l:type))
  if l:type == ''
    return
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

  " NOTE: THE PATTERN SHOULD BE IN THE LANGUAGE OF RIPGREP NOT VIM!!!
  " The weird looking (?:::)? is non-capturing parens to group the
  " possible '::' preceding the type.
  let l:patterns = []
  call add(l:patterns, '(?:^class|^define)\s+(?:::)?'.l:type.'\s*$')
  call add(l:patterns, '^[^#]\s+class\s*\{\s*(["''])(?:::)?'.l:type.'\1')
  call add(l:patterns, '^[^#]\s+(?:::)?'.l:type.'\s*\{\s*.*:')
  call add(l:patterns, '(include|contain)\s+(?:::)?'.l:type.'\s*$')
  call add(l:patterns, '^describe\s*(["''])(?:::)?'.l:type.'\2')
  let l:pattern = '(?:' . join(l:patterns, '|') . ')'
  call Debug(printf("The pattern is: %s", l:pattern))
  call s:Call_With_Cd('RgPuppet', l:pattern, printf("-g'!%s'", expand('%')))
endfunction

function! FzfSink(line)
  " Open the manifest for a resource selected in SelectResourcesFzf()
  call GoToPuppetManifest(a:line, 0)
endfunction

function! GoToPuppetManifest(line=getline('.'), extract=1)
  if a:extract == 0
    " Meaning 'line' contains the extracted resource name already
    let l:title = a:line
  else
    let l:resource = ExtractResource(a:line)
    if !empty(l:resource)
      let l:title = resource["title"]
    endif
  end

  if empty(l:title)
    echo "Coudn't extract resource name"
    return
  endif

  let module_path = substitute(l:title, '::', '/', 'g')

  if stridx(module_path, '/') == -1
    " Insert 'manifests' after the module name
    let manifest_path = module_path."/manifests/init"
  else
    " Insert 'manifests' after the module name
    " call Debug(module_path)
    let manifest_path = substitute(module_path, '\v^([^/]+)', '\1/manifests', '')
  endif

  " Add the ".pp" extension to form the manifest path
  let manifest_file = s:Call_With_Cd('findfile', manifest_path . '.pp', 'modules/;')

  " If the manifest is found, open it in a new tab
  if !empty(manifest_file)
      call s:Call_With_Cd('execute', printf('-tabedit %s', manifest_file))
  else
      echo printf("Manifest not found: %s.pp", manifest_path)
  endif
endfunction

function! SentenceCase(str, sep='::')
  return join(map(split(a:str, a:sep), 'substitute(v:val, "^.", "\\u&", "")'), a:sep)
endfunction

function! IsDefinedTypeInstance(resource)
  if index(["class", "defined_type"], a:resource["type"]) != -1
    return 0
  endif
  return 1
endfunction

function! PuppetDbLookup(line=getline('.'), fully_qualify=1)
  " Given a resource, look up which hosts use it.
  if empty(g:puppetdb_host)
    throw "g:puppetdb_host is not set! Please set to http(s)://<HOST>:<PORT>"
  endif

  let l:resource = ExtractResource(a:line, 1)
  if empty(l:resource)
    echo "Couldn't find a class or defined type on the current line."
    return
  endif

  let l:res_type = SentenceCase(l:resource["type"])
  if IsDefinedTypeInstance(l:resource)
    " Don't capitalize the title of an instance of a defined type. It's stored
    " in the db as is.
    let l:res_title = resource["title"]
  else
    let l:res_title = SentenceCase(resource["title"])
  endif

  if l:resource['type'] == 'defined_type'
    let l:script_args = l:res_title
    let l:term_title = l:res_title
  elseif l:resource['type'] == 'class' || a:fully_qualify == 1
    " Always fully qualify classes with their titles or the output will
    " potentially contain hundreds of lines.
    let l:script_args = join([l:res_type, l:res_title], ' ')
    let l:term_title = join([l:res_type, l:res_title], '%')
  else
    let l:script_args = l:res_type
    let l:term_title = l:res_type
  endif

  try
    let l:script = printf('%s/puppetdb.sh', g:plugin_dir)
    let l:cmd = printf("-tab call term_start('%s %s %s', {'term_name': '%s'})", l:script, g:puppetdb_host, l:script_args, l:term_title)
    call Debug(printf("Executing: %s",  l:cmd))
    exe l:cmd
  catch
    echoerr "An error occurred: " . v:exception
  endtry
endfunction

function! PuppetDbTypeTitleLookup(line=getline('.'))
  " Query PuppetDB by using both the type and title of the resource.
  " For example: Class+Mysql
  call PuppetDbLookup(a:line, 1)
endfunction

function! PuppetDbTypeLookup(line=getline('.'))
  " Query PuppetDB by using ONLY the type.
  " For example: some::defined_type
  "
  " This is allowed only for defined types since other built in types such as
  " 'class' would produce potentially hundreds of lines.
  call PuppetDbLookup(a:line, 0)
endfunction


function! RgPuppet(pattern, additional_opts=[])
  " Given a pattern, find all its matches in all puppet manifests
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
    call add(l:cmd_list, a:additional_opts)
  endif

  " Join the list into a single command string
  let l:cmd = join(l:cmd_list, ' ')
  call Debug("cmd:[start]".l:cmd."[end]")
  call fzf#vim#grep(l:cmd, fzf#vim#with_preview())
endfunction

command! -nargs=1 Rgp call RgPuppet(<f-args>)
nnoremap <Plug>(QueryPuppetdbAgainstManifest) :call QueryPuppetdbAgainstManifest()<cr>
