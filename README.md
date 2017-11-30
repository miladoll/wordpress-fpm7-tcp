# wordpress-fpm7-tcp
Docker-Compose File: wordpress-fpm7-tcp

最新の WordPress を PHP7 の PHP-FPM（TCP接続モード）で動作させる Dockerfile です。

## つかいかた

```bash
$ git clone https://github.com/miladoll/wordpress-fpm7-tcp.git
$ cp runtime_env.txt{.sample,}
  # 必要に応じて runtime_env.txt を編集
$ docker-compose up -d
```

* WordPressサイト  
  [http://localhost/](http://localhost/)
* WordPress管理画面  
  [http://localhost/wp-admin/](http://localhost/wp-admin/)

## 初回起動と永続性

### 初回起動時の動作

* WordPress
    * WordPressのデータベースがあるけれど空ならDROPします
    * WordPressのデータベース・ユーザがなければ作成します
    * `ドキュメントルート下/wp-config.php` がなければ WordPress のインストールをおこないます

### 永続性

* WordPress
    * ドキュメントルート下（WordPressインストールディレクトリ配下）は、すべて永続化されています（Dockerホストコンテキストディレクトリに保存）
* MySQL
    * データベースは永続化されます。`/var/lib/mysql` がすべてDockerホストコンテキストディレクトリに保存されます


## 構成

* mysql: MySQL
    * MySQLコンテナ。Dockerリポジトリのもの
    * `/var/lib/mysql` をホストに永続化します
* phpmyadmin: PHPMyAdmin
    * みんなだいすきPMA。Dockerリポジトリのもの
    * [http://localhost:8081/](http://localhost:8081/) でアクセスできます
    * 要らなきゃ消してね
* nginx: Nginx
    * Nginxコンテナ。Alpine 3.6ベースオリジナル
    * [http://localhost/](http://localhost/) でアクセスできます
    * `/var/www-nginx/wordpress` をホストに永続化し、wordpress と共有します
* wordpress: WordPress with PHP7/PHP-FPM
    * WordPressコンテナ。Alpine 3.6ベースオリジナル。PHP7/PHP-FPMを使用しており、TCP/IP 9000番ポートで通信します
    * `/var/www-nginx/wordpress` をホストに永続化し、nginx と共有します

## ふつうと異なるところ

* nginx の UID, GID を `docker-compose.yml` 中に記載した `UID_NGINX`, `GID_NGINX` で nginx, wordpress コンテナにおいて共通化しています
* nginx は wordpress の 9000番ポートが UP するまで起動待機します
* wordpress は mysql が SQL クエリを受け付けるまで起動待機します