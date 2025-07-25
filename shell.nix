{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Erlang and Elixir
    beam27Packages.erlang
    elixir
    
    # Build tools
    gcc
    gnumake
    cmake
    
    # System libraries for AntidoteDB
    # Note: AntidoteDB is typically run as a separate service
    # These are just for development dependencies
    
    # Additional development tools
    git
    inotify-tools
  ];
  
  shellHook = ''
    echo "Mana-Ethereum Development Environment"
    echo "Elixir: $(elixir --version)"
    echo "Erlang: $(erl -eval 'io:format("~s~n", [erlang:system_info(version)]), halt()' -noshell)"
    echo ""
    echo "Available commands:"
    echo "  mix deps.get    - Get dependencies"
    echo "  mix compile     - Compile the project"
    echo "  mix test        - Run tests"
    echo ""
    echo "Note: AntidoteDB should be running as a separate service"
    echo "  See: https://github.com/AntidoteDB/antidote for setup instructions"
    echo ""
    
    # Set Erlang include paths
    export ERL_LIBS="$(find /nix/store -name 'public_key-*' -type d | head -1 | xargs dirname):$ERL_LIBS"
  '';
} 