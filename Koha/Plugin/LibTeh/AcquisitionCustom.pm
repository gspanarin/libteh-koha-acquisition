package Koha::Plugin::LibTeh::AcquisitionCustom;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use C4::Context;
use C4::Auth;
use DBI;
use Data::Dumper;
use Template;
use utf8;
use Encode qw( encode_utf8 );
use C4::Output;
use C4::XSLT;
#use Koha::Plugin::LibTeh::AcquisitionCustom::Lib::DB;

our $VERSION = "1.0.0";

our $metadata = {
    name            => 'Розширене Комплектування та Облік Фонду',
    author          => 'Hennadii Panarin',
    description     => 'Модуль КСО (Надходження, Вибуття, Рух), Аудит фонду та RTF-друкарські форми',
    date_authored   => '2026-09-16',
    date_updated    => '2026-09-16',
    minimum_version => undef,
    version         => $VERSION,
};


sub new {
    my ( $class, $args ) = @_;
    $args->{metadata} = $metadata;
    $args->{metadata}->{class} = $class;

    my $self = $class->SUPER::new($args);
    #$self->{db} = Koha::Plugin::Com::LibTeh::AcquisitionCustom::DB->new();
    return $self;
}

# Хук для відображення в головному меню/інтранеті
sub intranet_head {
    my ($self) = @_;
    # Можна підключати додаткові JS/CSS на сторінки інтранету
}

# Головна точка входу при кліку на плагін
sub tool {
    my ( $self, $args ) = @_;
    my $cgi = $self->{cgi};

    # Перевірка та автоматична інсталяція за потреби
    $self->check_and_install();

    my $op = $cgi->param('op') || 'main';

    if ($op eq 'kso_in' || $op eq 'cud-save_kso1') {
        $self->page_kso_in();
    } elsif ( $op eq 'kso_out' ) {
        $self->page_kso_out();
    } elsif ( $op eq 'kso_movement' ) {
        $self->page_kso_movement();
    } elsif ( $op eq 'audit' ) {
        $self->page_audit();
    } elsif ( $op eq 'settings' ) {
        $self->page_settings();
    } else {
        $self->page_main();
    }
}

# Інсталяція: створення таблиць
sub install {
    my ( $self, $args ) = @_;
    my $dbh = C4::Context->dbh;

    # 1. Таблиця КСО 1 (Надходження)
    $dbh->do(qq{
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
    });

    # 2. Таблиця КСО 2 (Вибуття)
    $dbh->do(qq{
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
    });

    # 3. Таблиця Перевірки Фонду (Fund Audit)
    $dbh->do(qq{
        CREATE TABLE IF NOT EXISTS libteh_fund_audit (
            id INT AUTO_INCREMENT PRIMARY KEY,
            created_date DATE NOT NULL,
            audit_title VARCHAR(255) NOT NULL,
            branch_id VARCHAR(10) NOT NULL,
            status ENUM('planned', 'started', 'completed', 'canceled') DEFAULT 'planned',
            total_scanned INT DEFAULT 0,
            created_at DATETIME NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    });

    # 4. Збереження прапорця інсталяції в налаштування плагіна
    #$self->store_data({ installed => 1, schema_version => '1.0' });

    return 1;
}

# Деінсталяція: видалення службових таблиць
sub uninstall {
    my ( $self, $args ) = @_;
    my $dbh = C4::Context->dbh;

    $dbh->do("DROP TABLE IF EXISTS libteh_kso1;");
    $dbh->do("DROP TABLE IF EXISTS libteh_kso2;");
    $dbh->do("DROP TABLE IF EXISTS libteh_fund_audit;");

    return 1;
}

# Автоперевірка прапорця інсталяції
sub check_and_install {
    my ($self) = @_;
    unless ( $self->retrieve_data('installed') ) {
        $self->install();
    }
}

sub page_audit {
    my ($self) = @_;
    my $cgi = $self->{cgi};
    my $op  = $cgi->param('op') || '';

    if ( $op eq 'ajax_audit_scan' ) {
        my $audit_id = $cgi->param('audit_id');
        my $barcode  = $cgi->param('barcode');

        my $dbh = C4::Context->dbh;

        # 1. Пошук книги в таблиці items
        my $item = $dbh->selectrow_hashref(
            "SELECT i.itemnumber, i.homebranch, i.holdingbranch, b.title 
             FROM items i 
             JOIN biblio b ON i.biblionumber = b.biblionumber 
             WHERE i.barcode = ?", 
            undef, $barcode
        );

        if (!$item) {
            print $cgi->header(-type => 'application/json', -charset => 'UTF-8');
            print JSON::to_json({ success => 0, message => "Книгу не знайдено в каталозі за штрих-кодом: $barcode" });
            return;
        }

        # 2. Оновлення дати перевірки та атрибутів примірника
        $dbh->do(
            "UPDATE items SET datelastseen = NOW(), stack = ? WHERE itemnumber = ?",
            undef, "AUDIT_$audit_id", $item->{itemnumber}
        );

        # 3. Інкремент лічильника просканованого в таблиці аудиту
        $dbh->do(
            "UPDATE libteh_fund_audit SET total_scanned = total_scanned + 1 WHERE id = ?",
            undef, $audit_id
        );

        my $total_scanned = $dbh->selectrow_array(
            "SELECT total_scanned FROM libteh_fund_audit WHERE id = ?", 
            undef, $audit_id
        );

        # 4. Повернення відповіді
        print $cgi->header(-type => 'application/json', -charset => 'UTF-8');
        print JSON::to_json({
            success       => 1,
            barcode       => $barcode,
            title         => $item->{title},
            homebranch    => $item->{homebranch},
            total_scanned => $total_scanned
        });
        return;
    }
}

sub page_kso_in {
    my ($self) = @_;
    my $cgi    = $self->{cgi};
    my $dbh    = C4::Context->dbh;
    my $op     = $cgi->param('op') || '';

    # 1. Запит для виклику AJAX-даних окремого запису
    if ($op eq 'get_kso1') {
        my $id = $cgi->param('id');
        my $row = $dbh->selectrow_hashref("SELECT * FROM libteh_kso1 WHERE id = ?", undef, $id);
        
        print $cgi->header(-type => 'application/json', -charset => 'UTF-8');
        print JSON::to_json($row);
        return;
    }

    # 2. Запит для отримання списку примірників
    if ($op eq 'get_kso_items') {
        my $kso_id = $cgi->param('kso_id');
        # Припустимо, що id КСО зберігається у примірниках у полі stocknumber або спеціальному атрибуті/субполі
        my $items = $dbh->selectall_arrayref(
            "SELECT i.barcode, i.stocknumber, i.itemcallnumber, i.price, i.homebranch, i.biblionumber, b.title 
             FROM items i 
             LEFT JOIN biblio b ON i.biblionumber = b.biblionumber 
             WHERE i.booksellerid = ? OR i.stocknumber = ?",
            { Slice => {} }, $kso_id, "KSO_$kso_id"
        );

        print $cgi->header(-type => 'application/json', -charset => 'UTF-8');
        print JSON::to_json($items);
        return;
    }

    # 3. Збереження (INSERT / UPDATE)
    if ($op eq 'cud-save_kso1') {
        my $id               = $cgi->param('kso_id');
        my $reg_date         = $cgi->param('reg_date');
        my $doc_num          = $cgi->param('doc_num');
        my $doc_num_supplier = $cgi->param('doc_num_supplier');
        my $supplier_id      = $cgi->param('supplier_id') || undef;
        my $finance_source   = $cgi->param('finance_source');
        my $total_amount     = $cgi->param('total_amount') || 0;
        my $titles_count     = $cgi->param('titles_count') || 0;
        my $items_count      = $cgi->param('items_count') || 0;
        my $is_completed     = $cgi->param('is_completed') ? 1 : 0;
        my $user_id          = C4::Context->userenv ? C4::Context->userenv->{number} : undef;

        if ($id) {
            # Update
            $dbh->do(qq{
                UPDATE libteh_kso1 
                SET reg_date=?, doc_num=?, doc_num_supplier=?, supplier_id=?, finance_source=?, 
                    total_amount=?, titles_count=?, items_count=?, is_completed=?, updated_at=NOW(), updated_by=?
                WHERE id=? AND is_completed = 0
            }, undef, $reg_date, $doc_num, $doc_num_supplier, $supplier_id, $finance_source, $total_amount, $titles_count, $items_count, $is_completed, $user_id, $id);
        } else {
            # Insert
            $dbh->do(qq{
                INSERT INTO libteh_kso1 (reg_date, doc_num, doc_num_supplier, supplier_id, finance_source, total_amount, titles_count, items_count, is_completed, created_at, updated_at, created_by, updated_by)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW(), ?, ?)
            }, undef, $reg_date, $doc_num, $doc_num_supplier, $supplier_id, $finance_source, $total_amount, $titles_count, $items_count, $is_completed, $user_id, $user_id);
        }

        //print $cgi->redirect("/cgi-bin/koha/plugins/run.pl?class=" . $self->{class} . "&method=tool&op=kso_in");
        return;
    }

    # 4. Основне виведення сторінки
    my $kso_list = $dbh->selectall_arrayref(qq{
        SELECT k.*, aq.name AS supplier_name 
        FROM libteh_kso1 k
        LEFT JOIN aqbooksellers aq ON k.supplier_id = aq.id
        ORDER BY k.id DESC
    }, { Slice => {} });

    my $suppliers = $dbh->selectall_arrayref("SELECT id, name FROM aqbooksellers ORDER BY name ASC", { Slice => {} });

    my $template = $self->get_template({ file => 'intranet/templates/kso_in.tt' });
    $template->param(
        PLUGIN_CLASS => $self->{class},
        kso_list     => $kso_list,
        suppliers    => $suppliers,
    );

    print $cgi->header(-type => 'text/html', -charset => 'UTF-8');
    print $template->output();
}

sub page_kso_movement {
    my ($self) = @_;
    my $cgi    = $self->{cgi};
    my $dbh    = C4::Context->dbh;
    my $op     = $cgi->param('op') || '';

    # 1. Створення таблиці КСО 3, якщо ще не створена
    $dbh->do(qq{
        CREATE TABLE IF NOT EXISTS libteh_kso3_movement (
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

    # 2. Обробка видалення зафіксованого періоду
    if ($op eq 'delete_kso_movement') {
        my $id = $cgi->param('id');
        $dbh->do("DELETE FROM libteh_kso3_movement WHERE id = ?", undef, $id);
        print $cgi->redirect("/cgi-bin/koha/plugins/run.pl?class=" . $self->{class} . "&method=tool&op=kso_movement");
        return;
    }

    # 3. Обробка збереження зафіксованого періоду
    if ($op eq 'save_kso_movement') {
        $dbh->do(qq{
            INSERT INTO libteh_kso3_movement 
            (period_title, base_id, start_date, end_date, start_items, start_amount, in_items, in_amount, out_items, out_amount, end_items, end_amount, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
        }, undef,
            $cgi->param('period_title'),
            $cgi->param('base_id') || undef,
            $cgi->param('start_date'),
            $cgi->param('end_date'),
            $cgi->param('start_items') || 0,
            $cgi->param('start_amount') || 0,
            $cgi->param('in_items') || 0,
            $cgi->param('in_amount') || 0,
            $cgi->param('out_items') || 0,
            $cgi->param('out_amount') || 0,
            $cgi->param('end_items') || 0,
            $cgi->param('end_amount') || 0
        );

        print $cgi->redirect("/cgi-bin/koha/plugins/run.pl?class=" . $self->{class} . "&method=tool&op=kso_movement");
        return;
    }

    # 4. Логіка розрахунку руху
    my $selected_base_id = $cgi->param('base_period_id') || undef;
    my $start_date       = $cgi->param('start_date') || DateTime->now->strftime('%Y-01-01');
    my $end_date         = $cgi->param('end_date')   || DateTime->now->strftime('%Y-%m-%d');

    # Отримання базового стану з обраного запису КСО 3
    my $start_items  = 0;
    my $start_amount = 0.00;

    if ($selected_base_id) {
        my $base = $dbh->selectrow_hashref("SELECT end_items, end_amount FROM libteh_kso3_movement WHERE id = ?", undef, $selected_base_id);
        if ($base) {
            $start_items  = $base->{end_items}  || 0;
            $start_amount = $base->{end_amount} || 0.00;
        }
    }

    # Розрахунок надходжень із КСО 1 за період
    my $in_data = $dbh->selectrow_hashref(qq{
        SELECT SUM(items_count) AS items, SUM(total_amount) AS amount 
        FROM libteh_kso1 
        WHERE reg_date BETWEEN ? AND ?
    }, undef, $start_date, $end_date);

    my $in_items  = $in_data->{items}  || 0;
    my $in_amount = $in_data->{amount} || 0.00;

    # Розрахунок вибуття із КСО 2 за період
    my $out_data = $dbh->selectrow_hashref(qq{
        SELECT SUM(items_count) AS items, SUM(total_amount) AS amount 
        FROM libteh_kso2 
        WHERE reg_date BETWEEN ? AND ?
    }, undef, $start_date, $end_date);

    my $out_items  = $out_data->{items}  || 0;
    my $out_amount = $out_data->{amount} || 0.00;

    # Баланс на кінець періоду
    my $end_items  = $start_items + $in_items - $out_items;
    my $end_amount = $start_amount + $in_amount - $out_amount;

    # Отримання списку попередніх зафіксованих періодів
    my $previous_periods = $dbh->selectall_arrayref("SELECT * FROM libteh_kso3_movement ORDER BY id DESC", { Slice => {} });

    my $template = $self->get_template({ file => 'intranet/templates/kso_movement.tt' });
    $template->param(
        PLUGIN_CLASS     => $self->{class},
        previous_periods => $previous_periods,
        selected_base_id => $selected_base_id,
        start_date       => $start_date,
        end_date         => $end_date,
        calc => {
            start_items  => $start_items,
            start_amount => $start_amount,
            in_items     => $in_items,
            in_amount    => $in_amount,
            out_items    => $out_items,
            out_amount   => $out_amount,
            end_items    => $end_items,
            end_amount   => $end_amount,
        },
        movement_records => $previous_periods,
    );

    print $cgi->header(-type => 'text/html', -charset => 'UTF-8');
    print $template->output();
}

sub page_main {
    my ($self) = @_;
    my $cgi    = $self->{cgi};
    my $dbh    = C4::Context->dbh;

    # Збір швидкої статистики
    my ($total_kso1) = $dbh->selectrow_array("SELECT COUNT(*) FROM libteh_kso1");
    my ($total_kso2) = $dbh->selectrow_array("SELECT COUNT(*) FROM libteh_kso2");
    my ($active_audits) = $dbh->selectrow_array("SELECT COUNT(*) FROM libteh_fund_audit WHERE status = 'started'");
    
    # Спрощена перевірка наявності збережених RTF шаблонів
    my $total_rtf = 0; 
    eval {
        ($total_rtf) = $dbh->selectrow_array("SELECT COUNT(*) FROM libteh_rtf_templates");
    };

    my $template = $self->get_template({ file => 'intranet/templates/main.tt' });
    #my $template = $self->get_template({ file => $self->mbf_path('intranet/templates/main.tt') });
    #my $template = $self->get_template({ file => $self->mbf_path('main.tt') });
    
    $template->param(
        PLUGIN_CLASS => $self->{class},
        stats        => {
            total_kso1    => $total_kso1 || 0,
            total_kso2    => $total_kso2 || 0,
            active_audits => $active_audits || 0,
            total_rtf     => $total_rtf || 0,
        }
    );

    print $cgi->header(-type => 'text/html', -charset => 'UTF-8');
    print $template->output();
}

sub page_settings {
    my ($self, $args) = @_;
    my $cgi  = $self->{cgi};
    my $dbh  = C4::Context->dbh;

    # Отримання списку RTF шаблонів
    my $rtf_templates = $dbh->selectall_arrayref(
        "SELECT id, name, code, filename, DATE_FORMAT(updated_at, '%d.%m.%Y %H:%i') as updated_at 
         FROM libteh_rtf_templates ORDER BY id DESC",
        { Slice => {} }
    );

    # Отримання довідника RZN
    my $rzn_list = $dbh->selectall_arrayref(
        "SELECT id, code, name, sort_order FROM libteh_rzn ORDER BY sort_order ASC, id ASC",
        { Slice => {} }
    );

    my $template = $self->get_template({ file => 'intranet/templates/settings.tt' });
    $template->param(
        PLUGIN_CLASS  => $self->{class},
        rtf_templates => $rtf_templates,
        rzn_list      => $rzn_list,
        message       => $args->{message},
        message_type  => $args->{message_type},
    );

    print $cgi->header(-type => 'text/html', -charset => 'UTF-8');
    print $template->output();
}

# Обробник завантаження RTF-файлу
sub op_upload_rtf {
    my ($self) = @_;
    my $cgi    = $self->{cgi};
    my $dbh    = C4::Context->dbh;

    my $name     = $cgi->param('tpl_name');
    my $code     = $cgi->param('tpl_code');
    my $upload_fh = $cgi->upload('rtf_file');
    my $filename  = $cgi->param('rtf_file');

    if ($upload_fh) {
        local $/ = undef;
        my $file_content = <$upload_fh>;

        my $sth = $dbh->prepare("
            INSERT INTO libteh_rtf_templates (name, code, filename, content, updated_at) 
            VALUES (?, ?, ?, ?, NOW())
            ON DUPLICATE KEY UPDATE name=?, filename=?, content=?, updated_at=NOW()
        ");
        $sth->execute($name, $code, $filename, $file_content, $name, $filename, $file_content);

        return $self->page_settings({ message => "Шаблон '$name' успішно збережено!", message_type => "success" });
    }

    return $self->page_settings({ message => "Помилка завантаження файла.", message_type => "danger" });
}

# Збереження запису RZN (Додавання/Редагування)
sub op_save_rzn {
    my ($self) = @_;
    my $cgi    = $self->{cgi};
    my $dbh    = C4::Context->dbh;

    my $id   = $cgi->param('rzn_id');
    my $code = $cgi->param('rzn_code');
    my $name = $cgi->param('rzn_name');
    my $sort = $cgi->param('rzn_sort') || 10;

    if ($id) {
        $dbh->do("UPDATE libteh_rzn SET code=?, name=?, sort_order=? WHERE id=?", undef, $code, $name, $sort, $id);
    } else {
        $dbh->do("INSERT INTO libteh_rzn (code, name, sort_order) VALUES (?, ?, ?)", undef, $code, $name, $sort);
    }

    return $self->page_settings({ message => "Розділ знань успішно збережено!", message_type => "success" });
}

sub page_kso_out {
    my ($self, $args) = @_;
    my $cgi  = $self->{cgi};
    my $dbh  = C4::Context->dbh;

    # Список актів вибуття КСО 2
    my $kso2_list = $dbh->selectall_arrayref("
        SELECT 
            k.id,
            k.act_number,
            DATE_FORMAT(k.act_date, '%d.%m.%Y') AS act_date,
            DATE_FORMAT(k.act_date, '%Y-%m-%d') AS act_date_iso,
            k.reason_code,
            k.note,
            k.branchcode,
            b.branchname,
            COALESCE(SUM(i.total_items), 0) AS total_items,
            COALESCE(SUM(i.total_price), 0.00) AS total_price
        FROM libteh_kso2 k
        LEFT JOIN branches b ON k.branchcode = b.branchcode
        LEFT JOIN libteh_kso2_items i ON k.id = i.kso2_id
        GROUP BY k.id
        ORDER BY k.act_date DESC, k.id DESC
    ", { Slice => {} });

    # Загальні підсумки
    my $total_acts  = scalar @$kso2_list;
    my $total_docs  = 0;
    my $total_price = 0;

    foreach my $row (@$kso2_list) {
        $total_docs  += $row->{total_items};
        $total_price += $row->{total_price};
    }

    # Отримання списку підрозділів бібліотеки
    my $branches = $dbh->selectall_arrayref(
        "SELECT branchcode, branchname FROM branches ORDER BY branchname ASC",
        { Slice => {} }
    );

    my $template = $self->get_template({ file => 'intranet/templates/kso_out.tt' });
    $template->param(
        PLUGIN_CLASS => $self->{class},
        kso2_list    => $kso2_list,
        branches     => $branches,
        total_acts   => $total_acts,
        total_docs   => $total_docs,
        total_price  => sprintf("%.2f", $total_price),
        message      => $args->{message},
        message_type => $args->{message_type},
    );

    print $cgi->header(-type => 'text/html', -charset => 'UTF-8');
    print $template->output();
}

# Метод обробки скачування готового згенерованого звіту:
sub handle_rtf_download {
    my ($self, $cgi) = @_;
    my $code   = $cgi->param('code')   || 'kso2_act';
    my $act_id = $cgi->param('act_id') || 0;

    my $db = $self->{db};

    # 1. Отримуємо шаблон з БД (збережений у libteh_rtf_templates)
    my $tmpl_data = $db->get_rtf_template_by_code($code);
    unless ($tmpl_data && $tmpl_data->{content}) {
        print $cgi->header(-status => '404 Not Found');
        print "RTF-шаблон '$code' не знайдено.";
        return;
    }

    # 2. Отримуємо дані про Акт КСО-2 та його книги
    my $act_info = $db->get_kso2_by_id($act_id); # Допоміжний метод отримання 1 акту
    my $items    = $db->get_kso2_items($act_id); # Список примірників акту

    # 3. Ініціалізуємо парсер
    my $parser = Koha::Plugin::LibTeh::AcquisitionCustom::AcquisitionCustom::RTFParser->new({
        template_content => $tmpl_data->{content}
    });

    # 4. Підставляємо значення скалярних змінних
    $parser->process_vars({
        ACT_NUMBER  => $act_info->{act_number},
        ACT_DATE    => $act_info->{act_date_formatted},
        REASON_NAME => $act_info->{reason_name},
        TOTAL_QTY   => $act_info->{total_items},
        TOTAL_PRICE => $act_info->{total_price},
        BRANCH_NAME => $act_info->{branchname},
    });

    # 5. Заповнюємо табличну частину (список книжок)
    $parser->process_loop('ITEMS', $items);

    # 6. Віддаємо сформований файл користувачу
    my $output_rtf = $parser->get_content();
    my $filename   = "Act_KSO2_" . ($act_info->{act_number} || $act_id) . ".rtf";

    print $cgi->header(
        -type                   => 'application/rtf',
        -attachment             => $filename,
        -Content_Length         => length($output_rtf),
        -Access_Control_Allow_Origin => '*'
    );
    print $output_rtf;
}



1;