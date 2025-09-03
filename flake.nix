{
  description = "Ambiente de desenvolvimento Drupal completo e funcional";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    phpFpmSocket = "$PWD/php-fpm.sock";
  in {
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = [
        pkgs.php
        pkgs.postgresql
        pkgs.drupal
        pkgs.caddy
        pkgs.firefox
      ];

      shellHook = ''
          # --- Configuração do PostgreSQL ---
          export PGDATA="$PWD/.postgresql-data"
          export PGHOST="$PGDATA"
          mkdir -p "$PGDATA"

          echo "Limpando sessões antigas do PostgreSQL..."
          pg_ctl -D "$PGDATA" -m fast stop || true
          rm -f "$PGDATA/postmaster.pid"

          if [ ! -d "$PGDATA/base" ]; then
            echo "Inicializando o banco de dados PostgreSQL..."
            initdb -D "$PGDATA" --no-locale --encoding=UTF8 -A trust
          fi

          echo "Iniciando o PostgreSQL..."
          if pg_ctl -D "$PGDATA" -l "$PGDATA/logfile" -o "-c unix_socket_directories='$PGDATA'" start; then
            echo "✅ PostgreSQL iniciado com sucesso!"
          else
            echo "❌ Falha ao iniciar o PostgreSQL. Verifique os logs."
            exit 1
          fi

          # --- Configuração do PHP-FPM (O Intérprete PHP) ---
          cat > php-fpm.conf <<EOF
          [global]
          pid = $PWD/php-fpm.pid
          error_log = $PWD/php-fpm.log
          [www]
          listen = ${phpFpmSocket}
          pm = dynamic
          pm.max_children = 5
          pm.start_servers = 2
          pm.min_spare_servers = 1
          pm.max_spare_servers = 3
          EOF

          echo "Iniciando o serviço PHP-FPM em background..."
          php-fpm --fpm-config php-fpm.conf --daemonize

          # --- VERIFICAÇÃO DO PHP-FPM ---
          sleep 2 # Dá um tempo para o serviço iniciar
          if [ ! -S "${phpFpmSocket}" ]; then
              echo "❌ Falha ao iniciar o PHP-FPM. Verifique o log em php-fpm.log."
              exit 1
          fi
          echo "✅ PHP-FPM iniciado com sucesso!"


          # --- Configuração do Caddy (O Servidor Web) ---
          cat > Caddyfile <<EOF
          http://localhost:8000 {
            root * ${pkgs.drupal}/web
            file_server
            php_fastcgi unix/${phpFpmSocket}
          }
          EOF

          trap "echo 'Desligando todos os serviços...'; pg_ctl -D '$PGDATA' stop; kill \`cat $PWD/php-fpm.pid\`; caddy stop;" EXIT

          # --- AUTOMAÇÃO ---
          echo ""
          echo "✅ Ambiente completo! Todos os serviços estão prontos."
          echo "💡 Pressione Ctrl+C para parar o servidor e acessar o shell."
          (sleep 2 && firefox http://localhost:8000) &

          caddy run
    '';
    };
  };
}
