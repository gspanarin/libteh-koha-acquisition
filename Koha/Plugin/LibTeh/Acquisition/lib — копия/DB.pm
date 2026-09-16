package Koha::Plugin::LibTeh::Acquisition::Lib::DB;

use strict;
use warnings;
use utf8;
use C4::Context;

sub new {
    my ($class) = @_;
    my $self = {
        dbh => C4::Context->dbh,
    };
    return bless $self, $class;
}

# -----------------------------------------------------------------------------
# 1. Створене / Налаштування таблиць (Installer/Schema)
# -----------------------------------------------------------------------------

sub init_schema {
    my ($self) = @_;
    my $dbh = $self->{dbh};

    # КСО 1 - Надходження
    $dbh->do("
        CREATE TABLE IF NOT EXISTS libteh_kso1 (
            id INT AUTO_INCREMENT PRIMARY KEY,
            act_number VARCHAR(64) NOT NULL,
            act_date DATE NOT NULL,
            supplier_id INT DEFAULT NULL,
            supplier_name VARCHAR(255) DEFAULT NULL,
            doc_type VARCHAR(64) DEFAULT NULL,
            branchcode VARCHAR(10) DEFAULT NULL,
            note TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");

    # КСО 2 - Вибуття
    $dbh->do("
        CREATE TABLE IF NOT EXISTS libteh_kso2 (
            id INT AUTO_INCREMENT PRIMARY KEY,
            act_number VARCHAR(64) NOT NULL,
            act_date DATE NOT NULL,
            reason_code VARCHAR(64) NOT NULL,
            branchcode VARCHAR(10) DEFAULT NULL,
            note TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");

    # Деталізація примірників КСО 2
    $dbh->do("
        CREATE TABLE IF NOT EXISTS libteh_kso2_items (
            id INT AUTO_INCREMENT PRIMARY KEY,
            kso2_id INT NOT NULL,
            total_items INT DEFAULT 1,
            total_price DECIMAL(28,6) DEFAULT 0.000000,
            FOREIGN KEY (kso2_id) REFERENCES libteh_kso2(id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ");

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

    # Зчитані примірники аудиту
    $dbh->do("
        CREATE TABLE IF NOT EXISTS libteh_audit_items (
            id INT AUTO_INCREMENT PRIMARY KEY,
            audit_id INT NOT NULL,
            itemnumber INT NOT NULL,
            barcode VARCHAR(64) NOT NULL,
            scanned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY unique_audit_item (audit_id, itemnumber),
            FOREIGN KEY (audit_id) REFERENCES libteh_fund_audit(id) ON DELETE CASCADE
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

# -----------------------------------------------------------------------------
# 2. КСО 1 - НАДХОДЖЕННЯ (CRUD)
# -----------------------------------------------------------------------------

sub get_all_kso1 {
    my ($self) = @_;
    return $self->{dbh}->selectall_arrayref("
        SELECT k.*, DATE_FORMAT(k.act_date, '%d.%m.%Y') as act_date_formatted
        FROM libteh_kso1 k ORDER BY k.act_date DESC, k.id DESC
    ", { Slice => {} });
}

sub save_kso1 {
    my ($self, $data) = @_;
    my $dbh = $self->{dbh};

    if ($data->{id}) {
        my $sth = $dbh->prepare("
            UPDATE libteh_kso1 
            SET act_number=?, act_date=?, supplier_name=?, doc_type=?, branchcode=?, note=?
            WHERE id=?
        ");
        $sth->execute($data->{act_number}, $data->{act_date}, $data->{supplier_name}, $data->{doc_type}, $data->{branchcode}, $data->{note}, $data->{id});
        return $data->{id};
    } else {
        my $sth = $dbh->prepare("
            INSERT INTO libteh_kso1 (act_number, act_date, supplier_name, doc_type, branchcode, note)
            VALUES (?, ?, ?, ?, ?, ?)
        ");
        $sth->execute($data->{act_number}, $data->{act_date}, $data->{supplier_name}, $data->{doc_type}, $data->{branchcode}, $data->{note});
        return $dbh->{mysql_insertid};
    }
}

sub delete_kso1 {
    my ($self, $id) = @_;
    return $self->{dbh}->do("DELETE FROM libteh_kso1 WHERE id = ?", undef, $id);
}

# -----------------------------------------------------------------------------
# 3. КСО 2 - ВИБУТТЯ (CRUD)
# -----------------------------------------------------------------------------

sub get_all_kso2 {
    my ($self) = @_;
    return $self->{dbh}->selectall_arrayref("
        SELECT 
            k.id, k.act_number, k.reason_code, k.note, k.branchcode,
            DATE_FORMAT(k.act_date, '%d.%m.%Y') AS act_date,
            DATE_FORMAT(k.act_date, '%Y-%m-%d') AS act_date_iso,
            b.branchname,
            COALESCE(SUM(i.total_items), 0) AS total_items,
            COALESCE(SUM(i.total_price), 0.00) AS total_price
        FROM libteh_kso2 k
        LEFT JOIN branches b ON k.branchcode = b.branchcode
        LEFT JOIN libteh_kso2_items i ON k.id = i.kso2_id
        GROUP BY k.id
        ORDER BY k.act_date DESC, k.id DESC
    ", { Slice => {} });
}

sub save_kso2 {
    my ($self, $data) = @_;
    my $dbh = $self->{dbh};

    if ($data->{id}) {
        $dbh->do("
            UPDATE libteh_kso2 
            SET act_number=?, act_date=?, reason_code=?, branchcode=?, note=?
            WHERE id=?
        ", undef, $data->{act_number}, $data->{act_date}, $data->{reason_code}, $data->{branchcode}, $data->{note}, $data->{id});
        return $data->{id};
    } else {
        $dbh->do("
            INSERT INTO libteh_kso2 (act_number, act_date, reason_code, branchcode, note)
            VALUES (?, ?, ?, ?, ?)
        ", undef, $data->{act_number}, $data->{act_date}, $data->{reason_code}, $data->{branchcode}, $data->{note});
        return $dbh->{mysql_insertid};
    }
}

sub delete_kso2 {
    my ($self, $id) = @_;
    return $self->{dbh}->do("DELETE FROM libteh_kso2 WHERE id = ?", undef, $id);
}

# -----------------------------------------------------------------------------
# 4. АУДИТ ТА ПЕРЕВІРКА ФОНДУ (CRUD + AJAX Helpers)
# -----------------------------------------------------------------------------

sub get_active_audits {
    my ($self) = @_;
    return $self->{dbh}->selectall_arrayref("
        SELECT a.*, b.branchname AS location_name,
               (SELECT COUNT(*) FROM libteh_audit_items WHERE audit_id = a.id) AS scanned_count
        FROM libteh_fund_audit a
        LEFT JOIN branches b ON a.branchcode = b.branchcode
        WHERE a.status = 'started'
        ORDER BY a.id DESC
    ", { Slice => {} });
}

sub add_audit_scan {
    my ($self, $audit_id, $itemnumber, $barcode) = @_;
    my $dbh = $self->{dbh};

    my $sth = $dbh->prepare("
        INSERT INTO libteh_audit_items (audit_id, itemnumber, barcode, scanned_at)
        VALUES (?, ?, ?, NOW())
        ON DUPLICATE KEY UPDATE scanned_at = NOW()
    ");
    return $sth->execute($audit_id, $itemnumber, $barcode);
}

sub get_recent_scanned_items {
    my ($self, $audit_id, $limit) = @_;
    $limit ||= 10;

    return $self->{dbh}->selectall_arrayref("
        SELECT ai.barcode, DATE_FORMAT(ai.scanned_at, '%H:%i:%s') as scan_time,
               b.title, i.location, i.itemcallnumber
        FROM libteh_audit_items ai
        JOIN items i ON ai.itemnumber = i.itemnumber
        JOIN biblio b ON i.biblionumber = b.biblionumber
        WHERE ai.audit_id = ?
        ORDER BY ai.scanned_at DESC
        LIMIT ?
    ", { Slice => {} }, $audit_id, $limit);
}

# -----------------------------------------------------------------------------
# 5. РОЗДІЛИ ЗНАНЬ RZN (CRUD)
# -----------------------------------------------------------------------------

sub get_all_rzn {
    my ($self) = @_;
    return $self->{dbh}->selectall_arrayref("
        SELECT * FROM libteh_rzn ORDER BY sort_order ASC, id ASC
    ", { Slice => {} });
}

sub save_rzn {
    my ($self, $data) = @_;
    my $dbh = $self->{dbh};

    if ($data->{id}) {
        return $dbh->do("UPDATE libteh_rzn SET code=?, name=?, sort_order=? WHERE id=?", 
            undef, $data->{code}, $data->{name}, $data->{sort_order} || 10, $data->{id});
    } else {
        return $dbh->do("INSERT INTO libteh_rzn (code, name, sort_order) VALUES (?, ?, ?)", 
            undef, $data->{code}, $data->{name}, $data->{sort_order} || 10);
    }
}

sub delete_rzn {
    my ($self, $id) = @_;
    return $self->{dbh}->do("DELETE FROM libteh_rzn WHERE id = ?", undef, $id);
}

# -----------------------------------------------------------------------------
# 6. RTF-ШАБЛОНИ (CRUD)
# -----------------------------------------------------------------------------

sub get_all_rtf_templates {
    my ($self) = @_;
    return $self->{dbh}->selectall_arrayref("
        SELECT id, name, code, filename, DATE_FORMAT(updated_at, '%d.%m.%Y %H:%i') as updated_at
        FROM libteh_rtf_templates ORDER BY id DESC
    ", { Slice => {} });
}

sub get_rtf_template_by_code {
    my ($self, $code) = @_;
    return $self->{dbh}->selectrow_hashref("
        SELECT * FROM libteh_rtf_templates WHERE code = ? LIMIT 1
    ", undef, $code);
}

sub save_rtf_template {
    my ($self, $name, $code, $filename, $content) = @_;
    my $sth = $self->{dbh}->prepare("
        INSERT INTO libteh_rtf_templates (name, code, filename, content, updated_at) 
        VALUES (?, ?, ?, ?, NOW())
        ON DUPLICATE KEY UPDATE name=?, filename=?, content=?, updated_at=NOW()
    ");
    return $sth->execute($name, $code, $filename, $content, $name, $filename, $content);
}

sub delete_rtf_template {
    my ($self, $id) = @_;
    return $self->{dbh}->do("DELETE FROM libteh_rtf_templates WHERE id = ?", undef, $id);
}

1;