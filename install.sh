#!/bin/bash

# --------------------------------------------------------------------------
# Arquivo de instalação RISO-Web
# --------------------------------------------------------------------------

echo "Iniciando a instalação do RISO-Web...";

dependencias="apache2 php libapache2-mod-php mysql-client";

instalarDependencias(){
    echo "Instalando dependências... ";
    for dependencia in $dependencias
    do  
        echo -n " - $dependencia: "       
        if apt-get install -y $dependencia >> /dev/null
        then
            echo "OK";
        else
            echo "Erro";
            echo "Tente instalar manualmente. Comando: sudo apt-get install $dependencia";
            exit
        fi
    done

    # Caso não exista o arquivo, baixa o composer.phar
    echo -n " - composer: "; 
    if [ -e composer.phar ] || php -r "readfile('https://getcomposer.org/installer');" | php &> /dev/null
    then
        echo "OK";
    else
        echo "Erro";
        echo "Tente instalar manualmente o composer.";
        exit
    fi

    # Baixar dependências da API
    echo -n "Instalando dependências da API... "; 
    if cd src/api && php ../../composer.phar install &> /dev/null ; cd ../..
    then
        echo "OK";
    else
        echo "Erro";
        echo "Tente instalar manualmente o composer.";
        exit
    fi
}

copiarArquivos(){
    echo -n "Substituindo arquivos no Apache... ";
    rm -rf /var/www/riso-web 2>> /dev/null    
    if cp -R src /var/www/riso-web >> /dev/null
    then
        echo "OK";
    else
        echo "Erro";
        exit
    fi

    # Copia a configuração do MySQL para o PHP
    cp conf/configuracao.php /var/www/riso-web/api/configuracao.php
}

configurarApache(){
    echo -n "Qual a porta a ser instalado o RISO-Web ? [Padrão: 80]: ";
    read porta

    # Extrai apenas os números do que foi lido
    porta=`echo -n "$porta" | tr -dc '0-9'`

    # Caso a porta esteja vazia, define como 80
    [ -z "$porta" ] && porta=80

    configuracaoAtual=`cat /etc/apache2/ports.conf | grep "\<Listen $porta\>"`;

    # Verifica se já o apache ainda não está está configurado para escutar a porta escolhida
    if [ -z  "$configuracaoAtual" ]; then
        echo -n "Adicionar a porta $porta nas portas do Apache2 ? [S/n]: ";
        read resposta        
        [ "$resposta" != "n" -a "$resposta" != "N" ] && echo "Listen $porta" >> /etc/apache2/ports.conf && echo "Porta adicionada";
    fi
    
    # Cria arquivo riso-web.conf
    echo -n "Criando VirtualHost no Apache... ";
    echo "<VirtualHost *:$porta>" > conf/riso-web.conf
    echo "  ServerAdmin webmaster@localhost" >> conf/riso-web.conf
    echo "  DocumentRoot /var/www/riso-web" >> conf/riso-web.conf
    echo "  ErrorLog ${APACHE_LOG_DIR}/error.log" >> conf/riso-web.conf
    echo "  CustomLog ${APACHE_LOG_DIR}/access.log combined" >> conf/riso-web.conf
    echo "  <Directory /var/www/riso-web>" >> conf/riso-web.conf
    echo "    AllowOverride All" >> conf/riso-web.conf
    echo "  </Directory>" >> conf/riso-web.conf
    echo "</VirtualHost>" >> conf/riso-web.conf

    # Substitui o VirtualHost existente e ativa ele
    rm /etc/apache2/sites-available/riso-web.conf /etc/apache2/sites-enabled/riso-web.conf 2>> /dev/null    
    if cp conf/riso-web.conf /etc/apache2/sites-available/riso-web.conf >> /dev/null
    then
        echo "OK";
    else
        echo "Erro";
        exit
    fi

    echo "Verificando Virtual Hosts atuais...";
    # Verifica todos os arquivos de sites habilitados do Apache
    ativarVirtualHost=1;
    for arquivo in /etc/apache2/sites-enabled/*.conf; do
        portaAtivada=`cat $arquivo 2> /dev/null | grep VirtualHost | grep :$porta`
        if [ ! -z  "$portaAtivada" ]; then
            echo -n "$(basename $arquivo) já está configurado com a porta $porta, remover ? [S/n]: ";
            read resposta        
            if [ "$resposta" != "n" -a "$resposta" != "N" ]
            then
                rm $arquivo;
            else
                ativarVirtualHost=0;
            fi
        fi
    done

    if [ $ativarVirtualHost == 1 ]
    then
        echo -n "Ativando Virtual Host no Apache... ";
        if ln -s /etc/apache2/sites-available/riso-web.conf /etc/apache2/sites-enabled/riso-web.conf >> /dev/null
        then
            echo "OK";
        else
            echo "Erro";
            exit
        fi
    else
        echo "O Virtual Host não pode ser ativado na porta $porta porque já existe um site configurado nessa porta.";
        exit;
    fi
    echo -n "Ativando Mod Rewrite... "
    if a2enmod rewrite &>> /dev/null
    then
        echo "OK";
    else
        echo "Erro";
        exit
    fi
}

reiniciarApache(){
    echo -n "Reiniciando o Apache... "
    
    if service apache2 restart 2>> /dev/null
    then    
        echo "OK";
        endereco="http://localhost";
        [ "$porta" != "80" ] && endereco=$endereco":$porta"
        echo "O sistema está agora funcionando em $endereco/";
    else   
        echo "Erro";
    fi
}

configurarMySQL(){

    echo -n "Instalar MySQL Server local ? [S/n]: ";
    read resposta        
    [ "$resposta" != "n" -a "$resposta" != "N" ] && apt-get install -y mysql-server

    echo "Configuração do MySQL"
    echo -n "Endereço do banco de dados [Padrão: localhost]: ";

    # Lê o endereço do banco de dados e caso vaizo, define como localhost
    read endereco
    [ -z "$endereco" ] && endereco="localhost"

    echo -n "Usuário do banco de dados [Padrão: root]: ";

    # Lê o usuário do banco de dados e caso vaizo, define como root
    read usuario
    [ -z "$usuario" ] && usuario="root";

    echo -n "Digite a senha para o usuário $usuario: ";

    # Lê a senha do banco de dados
    read -s senha
    
    echo ""; # Quebra de linha
    
    echo -n "Importando banco de dados SQL... ";
    
    if mysql -h $endereco -u $usuario -p$senha < conf/database.sql 2>> /dev/null
    then    
        echo "OK";
    else   
        echo "Erro";
        exit
    fi

    # Cria arquivo de configuração para o PHP
    echo "<?php" > conf/configuracao.php
    echo "define('MYSQL_HOST', '$endereco');" >> conf/configuracao.php
    echo "define('MYSQL_USER', '$usuario');" >> conf/configuracao.php
    echo "define('MYSQL_PASSWORD', '$senha');" >> conf/configuracao.php
    echo "define('MYSQL_DB_NAME', 'riso-web');" >> conf/configuracao.php
    echo "?>" >> conf/configuracao.php
}

instalarRisoWeb(){   
    # Instala as dependências
    instalarDependencias

    # Configura o apache
    configurarApache

    # Configura o MySQL
    configurarMySQL


    # Substitui arquivos do RISO-Web no apache
    copiarArquivos

    # Reinicia o apache
    reiniciarApache
}

#Verifica se usuário é o root antes de executar.
USER=`id -u`
if [ $USER == '0' ]; then
    clear
    instalarRisoWeb
else
    echo "Só o root pode fazer isso, jovenzinho! Use: sudo make"
fi