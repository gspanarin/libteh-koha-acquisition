package Koha::Plugin::LibTeh::Acquisition::Lib::RTFParser;

use strict;
use warnings;
use utf8;
use Encode qw(decode encode);

sub new {
    my ($class, $args) = @_;
    my $self = {
        template_content => $args->{template_content} || '',
    };
    return bless $self, $class;
}

# -----------------------------------------------------------------------------
# 1. Завантаження вмісту шаблону
# -----------------------------------------------------------------------------
sub load_template {
    my ($self, $content) = @_;
    $self->{template_content} = $content;
}

# -----------------------------------------------------------------------------
# 2. Перетворення кириличних символів UTF-8 у сумісний для RTF Unicode-escape
#    (Наприклад: 'А' -> '\u1040?', 'акти' -> '\u1072?\u1082?\u1090?\u1080?')
# -----------------------------------------------------------------------------
sub rtf_encode {
    my ($text) = @_;
    return '' unless defined $text;

    # Якщо текст не у прапорці utf8, декодуємо його
    $text = decode('utf-8', $text) unless utf8::is_utf8($text);

    my $rtf_text = '';
    for my $char (split //, $text) {
        my $ord = ord($char);
        if ($ord > 127) {
            # RTF Unicode escape форма: \uN? де N - signed int16 (або 0..65535)
            if ($ord > 32767) {
                $ord -= 65536;
            }
            $rtf_text .= sprintf("\\u%d?", $ord);
        } else {
            # Екранування спецсимволів RTF
            if ($char eq '\\' || $char eq '{' || $char eq '}') {
                $rtf_text .= '\\' . $char;
            } else {
                $rtf_text .= $char;
            }
        }
    }
    return $rtf_text;
}

# -----------------------------------------------------------------------------
# 3. Заміна простих змінних {VARIABLE_NAME} -> Значення
# -----------------------------------------------------------------------------
sub process_vars {
    my ($self, $vars) = @_;
    return unless $self->{template_content};

    while (my ($key, $val) = each %{$vars}) {
        my $encoded_val = rtf_encode($val);
        my $pattern     = quotemeta('{' . $key . '}');
        $self->{template_content} =~ s/$pattern/$encoded_val/g;
    }
}

# -----------------------------------------------------------------------------
# 4. Обробка списків / циклів для таблиць у RTF
#    Синтаксис у RTF шаблоні:
#    {START_LOOP_ITEMS} ...рядок таблиці RTF із {ITEM_TITLE}, {PRICE}... {END_LOOP_ITEMS}
# -----------------------------------------------------------------------------
sub process_loop {
    my ($self, $loop_name, $items_arrayref) = @_;
    return unless $self->{template_content};

    my $start_tag = quotemeta('{START_LOOP_' . uc($loop_name) . '}');
    my $end_tag   = quotemeta('{END_LOOP_' . uc($loop_name) . '}');

    # Шукаємо блок між тегами циклу
    if ($self->{template_content} =~ /($start_tag)(.*?)($end_tag)/s) {
        my $row_template = $2;
        my $generated_rows = '';

        for my $item (@{$items_arrayref}) {
            my $current_row = $row_template;

            while (my ($key, $val) = each %{$item}) {
                my $encoded_val = rtf_encode($val);
                my $pattern     = quotemeta('{' . uc($key) . '}');
                $current_row =~ s/$pattern/$encoded_val/g;
            }
            $generated_rows .= $current_row;
        }

        # Замінюємо шаблон циклу згенерованими рядками
        $self->{template_content} =~ s/$start_tag.*?$end_tag/$generated_rows/s;
    }
}

# -----------------------------------------------------------------------------
# 5. Отримання підсумкового RTF контенту
# -----------------------------------------------------------------------------
sub get_content {
    my ($self) = @_;
    return $self->{template_content};
}

1;