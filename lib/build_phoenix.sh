download_node() {
  local node_url="http://s3pository.heroku.com/node/v$node_version/node-v$node_version-linux-x64.tar.gz"

  if [ ! -f ${cached_node} ]; then
    info "Downloading node ${node_version}..."
    curl -s ${node_url} -o ${cached_node}
    cleanup_old_node
  else
    info "Using cached node ${node_version}..."
  fi
}

cleanup_old_node() {
  local old_node_path=$cache_path/node-v$old_node-linux-x64.tar.gz


  if [ "$old_node" != "$node_version" ] && [ -f $old_node_path ]; then
    info "Cleaning up old node and old dependencies in cache"
    rm $old_node_path
    rm -rf $cache_path/node_modules

    local bower_components_path=$cache_path/bower_components

    if [ -d $bower_components_path ]; then
      rm -rf $bower_components_path
    fi
  fi
}

install_node() {
  info "Installing node $node_version..."
  tar xzf ${cached_node} -C /tmp

  # Move node (and npm) into .heroku/node and make them executable
  mv /tmp/node-v$node_version-linux-x64/* $heroku_path/node
  chmod +x $heroku_path/node/bin/*
  PATH=$heroku_path/node/bin:$PATH
}

install_npm() {
  # Optionally bootstrap a different npm version
  if [ ! $npm_version ] || [[ `npm --version` == "$npm_version" ]]; then
    info "Using default npm version"
  else
    info "Downloading and installing npm $npm_version (replacing version `npm --version`)..."
    npm install --unsafe-perm --quiet -g npm@$npm_version 2>&1 >/dev/null | indent
  fi
}

install_and_cache_deps() {
  info "Installing and caching node modules"
  cd $cache_path
  cp -f $build_path/package.json ./

  npm install --quiet --unsafe-perm --userconfig $build_path/npmrc 2>&1 | indent
  npm rebuild 2>&1 | indent
  npm --unsafe-perm prune 2>&1 | indent
  cp -r node_modules $build_path
  PATH=$build_path/node_modules/.bin:$PATH
  install_bower_deps
  cd - > /dev/null
}

install_bower_deps() {
  local bower_path=$build_path/bower.json

  if [ -f $bower_path ]; then
    info "Installing and caching bower components"
    cp -f $bower_path ./
    bower install
    cp -r bower_components $build_path
  fi
}

compile() {
  cd $build_path
  PATH=$build_path/.platform_tools/erlang/bin:$PATH
  PATH=$build_path/.platform_tools/elixir/bin:$PATH

  run_compile

  cd - > /dev/null
}

run_compile() {
  local custom_compile="${build_path}/${compile}"

  if [ -f $custom_compile ]; then
    info "Running custom compile"
    source $custom_compile 2>&1 | indent
  else
    info "Running default compile"
    source ${build_pack_path}/${compile} 2>&1 | indent
  fi
}

cache_versions() {
  info "Caching versions for future builds"
  echo `node --version` > $cache_path/node-version
  echo `npm --version` > $cache_path/npm-version
}

write_profile() {
  info "Creating runtime environment"
  mkdir -p $build_path/.profile.d
  local export_line="export PATH=\"\$HOME/.heroku/node/bin:\$HOME/bin:\$HOME/node_modules/.bin:\$PATH\"
                     export MIX_ENV=${MIX_ENV}"
  echo $export_line >> $build_path/.profile.d/phoenix_static_buildpack_paths.sh
}
