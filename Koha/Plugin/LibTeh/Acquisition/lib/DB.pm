package Koha::Plugin::LibTeh::Acquisition::lib::DB;

use Modern::Perl;

use strict;
use warnings;
use utf8;
use C4::Context;

sub new {
    my ($class) = @_;
    my $self = {};
    return bless $self, $class;
}

# Допоміжний метод для отримання свіжого $dbh
sub dbh {
    my ($self) = @_;
    return C4::Context->dbh;
}

# -----------------------------------------------------------------------------
# 1. Створене / Налаштування таблиць (Installer/Schema)
# -----------------------------------------------------------------------------

sub init_schema {

    my ($self) = @_;
    my $dbh = $self->dbh;
    # КСО 1 - Надходження
    $dbh->do("
        CREATE TABLE IF NOT EXISTS libteh_kso1 (
            id INT AUTO_INCREMENT PRIMARY KEY,
            reg_date DATE NOT NULL,
            doc_num VARCHAR(100) NOT NULL,
            doc_num_supplier VARCHAR(100),
            supplier_id INT,
            finance_source VARCHAR(250),
            titles_count INT DEFAULT 0,
            items_count INT DEFAULT 0,
            total_amount DECIMAL(10,2) DEFAULT 0.00,
            is_completed TINYINT(1) DEFAULT 0,
            metadata_xml TEXT,
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL,
            created_by INT,
            updated_by INT
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");

    # КСО 2 - Вибуття
    $dbh->do("
        CREATE TABLE IF NOT EXISTS libteh_kso2 (
            id INT AUTO_INCREMENT PRIMARY KEY,
            reg_date DATE NOT NULL,
            act_num VARCHAR(100) NOT NULL,
            reason_code VARCHAR(50),
            titles_count INT DEFAULT 0,
            items_count INT DEFAULT 0,
            total_amount DECIMAL(10,2) DEFAULT 0.00,
            is_completed TINYINT(1) DEFAULT 0,
            metadata_xml TEXT,
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL,
            created_by INT,
            updated_by INT
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");

    # КСО 3 - рух фонду
    $dbh->do(qq{
        CREATE TABLE IF NOT EXISTS libteh_kso3 (
            id INT AUTO_INCREMENT PRIMARY KEY,
            period_title VARCHAR(255) NOT NULL,
            base_id INT NULL,
            start_date DATE NOT NULL,
            end_date DATE NOT NULL,
            start_items INT DEFAULT 0,
            start_amount DECIMAL(10,2) DEFAULT 0.00,
            in_items INT DEFAULT 0,
            in_amount DECIMAL(10,2) DEFAULT 0.00,
            out_items INT DEFAULT 0,
            out_amount DECIMAL(10,2) DEFAULT 0.00,
            end_items INT DEFAULT 0,
            end_amount DECIMAL(10,2) DEFAULT 0.00,
            created_at DATETIME NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    });
    
    # Аудит фонду (Сеанси перевірки)
    $dbh->do("
        CREATE TABLE IF NOT EXISTS libteh_fund_audit (
            id INT AUTO_INCREMENT PRIMARY KEY,
            title VARCHAR(255) NOT NULL,
            branchcode VARCHAR(10) NOT NULL,
            status ENUM('started', 'completed') DEFAULT 'started',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");

   

    # Розділи знань (RZN)
    $dbh->do("
        CREATE TABLE IF NOT EXISTS libteh_rzn (
            id INT AUTO_INCREMENT PRIMARY KEY,
            code VARCHAR(32) NOT NULL,
            name VARCHAR(255) NOT NULL,
            sort_order INT DEFAULT 10
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");

    # RTF-шаблони документів
    $dbh->do("
        CREATE TABLE IF NOT EXISTS libteh_rtf_templates (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(255) NOT NULL,
            code VARCHAR(64) NOT NULL UNIQUE,
            filename VARCHAR(255) NOT NULL,
            content LONGBLOB NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");
    
    
}


sub destruct_schema {
    my ($self) = @_;
    my $dbh = $self->dbh;
    
    $dbh->do("DROP TABLE IF EXISTS libteh_kso1;");
    $dbh->do("DROP TABLE IF EXISTS libteh_kso2;");
    $dbh->do("DROP TABLE IF EXISTS libteh_kso3;");
    $dbh->do("DROP TABLE IF EXISTS libteh_fund_audit;");
    $dbh->do("DROP TABLE IF EXISTS libteh_rzn;");
    $dbh->do("DROP TABLE IF EXISTS libteh_rtf_templates;");  
}
   
            
sub save_kso1 {
    my ($self, $data) = @_;
    my $dbh = $self->dbh;

    if ($data->{id}) {
        my $sth = $dbh->prepare("
            UPDATE libteh_kso1 
            SET 
                reg_date=?, 
                doc_num=?, 
                doc_num_supplier=?, 
                supplier_id=?, 
                finance_source=?, 
                total_amount=?, 
                titles_count=?, 
                items_count=?, 
                is_completed=?, 
                updated_by=?
            WHERE id=?
        ");
        $sth->execute(
            $data->{reg_date}, 
            $data->{doc_num},
            $data->{doc_num_supplier}, 
            $data->{supplier_id}, 
            $data->{finance_source}, 
            $data->{total_amount}, 
            $data->{titles_count}, 
            $data->{items_count}, 
            $data->{is_completed}, 
            $data->{user_id}, 
            $data->{id});
        return $data->{id};
    } else {
        my $sth = $dbh->prepare("
            INSERT INTO libteh_kso1 (
                reg_date, 
                doc_num, 
                doc_num_supplier, 
                supplier_id, 
                finance_source, 
                total_amount, 
                titles_count, 
                items_count, 
                is_completed, 
                created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");
        $sth->execute(
            $data->{reg_date}, 
            $data->{doc_num}, 
            $data->{doc_num_supplier}, 
            $data->{supplier_id}, 
            $data->{finance_source}, 
            $data->{total_amount}, 
            $data->{titles_count}, 
            $data->{items_count}, 
            $data->{is_completed}, 
            $data->{user_id});
        return $dbh->{mysql_insertid};
    }
}













1;