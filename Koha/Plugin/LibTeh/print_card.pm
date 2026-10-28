package Koha::Plugin::LibTeh::print_card;

use Modern::Perl;
use strict;
use warnings;
use base qw(Koha::Plugins::Base);

use C4::Context;
use C4::Output qw( output_html_with_http_headers );
use CGI qw( -utf8 );
use Koha::Biblios;
use Koha::RecordProcessor;
use HTML::FormatRTF;
use HTML::Entities;
use Encode qw( encode FB_DEFAULT );
use C4::Biblio qw( 
    GetMarcFromKohaField
    GetMarcStructure  
    GetAuthorisedValueDesc 
);
use File::Slurp qw( read_file write_file );
use utf8;
use Data::Dumper;

our $VERSION = "1.1.0";

our $metadata = {
    name            => 'Друк каталожних карток',
    author          => 'Hennadii Panarin',
    description     => 'Друк каталожних карток, топокарток, систематичних карток, формулярів тощо.',
    date_authored   => '2026-09-16',
    date_updated    => '2026-09-19',
    minimum_version => undef,
    version         => $VERSION,
};

sub new {
    my ( $class, $args ) = @_;
    $args->{metadata} = $metadata;
    $args->{metadata}->{class} = $class;
    
    my $self = $class->SUPER::new($args);
    return $self;
}

sub install {
    my ( $self, $args ) = @_;
    
    # Значення за замовчуванням для ISBD (MARC21)
    my $default_marc21 = <<'ISBD';
#080|<b>|{ 080a }|</b><br/>
#100|<b>|{ 100a }{ 100b }{ 100c }{ 100d }{ 110a }{ 110b }{ 110c }{ 110d }{ 110e }{ 110f }{ 110g }{ 130a }{ 130d }{ 130f }{ 130g }{ 130h }{ 130k }{ 130l }{ 130m }{ 130n }{ 130o }{ 130p }{ 130r }{ 130s }{ 130t }|</b><br/>
#245||{ 245a }{ : 245b }{ 245f }{ 245g }{ 245k }{ 245n }{ 245p }{ 245s }{ 245h }|
#246||{ : 246i }{ 246a }{ 246b }{ 246f }{ 246g }{ 246n }{ 246p }{ 246h }|
#242||{ = 242a }{ 242b }{ 242n }{ 242p }{ 242h }|
#245| / |{ 245c }|
#242||{ = 242c }|
#250| - |{ 250a }{ 250b }|
#254|, |{ 254a }|
#255|, |{ 255a }{ 255b }{ 255c }{ 255d }{ 255e }{ 255f }{ 255g }|
#256|, |{ 256a }|
#257|, |{ 257a }|
#258|, |{ 258a }{ 258b }|
#260|. - |{ 260a : }{ 260b }{, 260c }|
#300|. - |{ 300a }{ 300b }{ 300c }{ 300d }{ 300e }{ 300f }{ 300g }|
#546|. - |{ 546a }|
#306| - |{ 306a }|
#307| - |{ 307a }{ 307b }|
#310| - |{ 310a }{ 310b }|
#321| - |{ 321a }{ 321b }|
#340| - |{ 3403 }{ 340a }{ 340b }{ 340c }{ 340d }{ 340e }{ 340f }{ 340h }{ 340i }|
#342| - |{ 342a }{ 342b }{ 342c }{ 342d }{ 342e }{ 342f }{ 342g }{ 342h }{ 342i }{ 342j }{ 342k }{ 342l }{ 342m }{ 342n }{ 342o }{ 342p }{ 342q }{ 342r }{ 342s }{ 342t }{ 342u }{ 342v }{ 342w }|
#343| - |{ 343a }{ 343b }{ 343c }{ 343d }{ 343e }{ 343f }{ 343g }{ 343h }{ 343i }|
#351| - |{ 3513 }{ 351a }{ 351b }{ 351c }|
#352| - |{ 352a }{ 352b }{ 352c }{ 352d }{ 352e }{ 352f }{ 352g }{ 352i }{ 352q }|
#362| - |{ 362a }{ 351z }|
#440| - |{ 440a }{ 440n }{ 440p }{ 440v }{ 440x }|.
#490| - |({ 490a }{ 490v }{ 490x })|.
#800| - |{ 800a }{ 800b }{ 800c }{ 800d }{ 800e }{ 800f }{ 800g }{ 800h }{ 800j }{ 800k }{ 800l }{ 800m }{ 800n }{ 800o }{ 800p }{ 800q }{ 800r }{ 800s }{ 800t }{ 800u }{ 800v }|.
#810| - |{ 810a }{ 810b }{ 810c }{ 810d }{ 810e }{ 810f }{ 810g }{ 810h }{ 810k }{ 810l }{ 810m }{ 810n }{ 810o }{ 810p }{ 810r }{ 810s }{ 810t }{ 810u }{ 810v }|.
#811| - |{ 811a }{ 811c }{ 811d }{ 811e }{ 811f }{ 811g }{ 811h }{ 811k }{ 811l }{ 811n }{ 811p }{ 811q }{ 811s }{ 811t }{ 811u }{ 811v }|.
#830| - |{ 830a }{ 830d }{ 830f }{ 830g }{ 830h }{ 830k }{ 830l }{ 830m }{ 830n }{ 830o }{ 830p }{ 830r }{ 830s }{ 830t }{ 830v }|.
#020| - <b>ISBN: </b>|{ 020a }|
#022| - <b>ISSN: </b>|{ 022a }|
#500|<br/><br/>|{ 5003 }{ 500a }|
#501|<br/><br/>|{ 501a }|
#502|<br/><br/>|{ 502a }|
#504|<br/><br/>|{ 504a }|
#505|<br/><br/>|{ 505a }{ 505t }{ 505r }{ 505g }{ 505u }|
#506|<br/><br/>|{ 5063 }{ 506a }{ 506b }{ 506c }{ 506d }{ 506u }|
#507|<br/><br/>|{ 507a }{ 507b }|
#508|<br/><br/>|{ 508a }{ 508a }|
#510|<br/><br/>|{ 5103 }{ 510a }{ 510x }{ 510c }{ 510b }|
#511|<br/><br/>|{ 511a }|
#513|<br/><br/>|{ 513a }{ 513b }|
#514|<br/><br/>|{ 514z }{ 514a }{ 514b }{ 514c }{ 514d }{ 514e }{ 514f }{ 514g }{ 514h }{ 514i }{ 514j }{ 514k }{ 514m }{ 514u }|
#515|<br/><br/>|{ 515a }|
#516|<br/><br/>|{ 516a }|
#518|<br/><br/>|{ 5183 }{ 518a }|
#520|<br/><br/>|{ 5203 }{ 520a }{ 520b }{ 520u }|
#521|<br/><br/>|{ 5213 }{ 521a }{ 521b }|
#522|<br/><br/>|{ 522a }|
#524|<br/><br/>|{ 524a }|
#525|<br/><br/>|{ 525a }|
#526|<br/><br/>|{\n510i }{\n510a }{ 510b }{ 510c }{ 510d }{\n510x }|
#530|<br/><br/>|{\n5063 }{\n506a }{ 506b }{ 506c }{ 506d }{\n506u }|
#533|<br/><br/>|{\n5333 }{\n533a }{\n533b }{\n533c }{\n533d }{\n533e }{\n533f }{\n533m }{\n533n }|
#534|<br/><br/>|{\n533p }{\n533a }{\n533b }{\n533c }{\n533d }{\n533e }{\n533f }{\n533m }{\n533n }{\n533t }{\n533x }{\n533z }|
#535|<br/><br/>|{\n5353 }{\n535a }{\n535b }{\n535c }{\n535d }|
#538|<br/><br/>|{\n5383 }{\n538a }{\n538i }{\n538u }|
#540|<br/><br/>|{\n5403 }{\n540a }{ 540b }{ 540c }{ 540d }{\n520u }|
#544|<br/><br/>|{\n5443 }{\n544a }{\n544b }{\n544c }{\n544d }{\n544e }{\n544n }|
#545|<br/><br/>|{\n545a }{ 545b }{\n545u }|
#547|<br/><br/>|{\n547a }|
#550|<br/><br/>|{ 550a }|
#552|<br/><br/>|{ 552z }{ 552a }{ 552b }{ 552c }{ 552d }{ 552e }{ 552f }{ 552g }{ 552h }{ 552i }{ 552j }{ 552k }{ 552l }{ 552m }{ 552n }{ 562o }{ 552p }{ 552u }|
#555|<br/><br/>|{ 5553 }{ 555a }{ 555b }{ 555c }{ 555d }{ 555u }|
#556|<br/><br/>|{ 556a }{ 506z }|
#563|<br/><br/>|{ 5633 }{ 563a }{ 563u }|
#565|<br/><br/>|{ 5653 }{ 565a }{ 565b }{ 565c }{ 565d }{ 565e }|
#567|<br/><br/>|{ 567a }|
#580|<br/><br/>|{ 580a }|
#581|<br/><br/>|{ 5633 }{ 581a }{ 581z }|
#584|<br/><br/>|{ 5843 }{ 584a }{ 584b }|
#585|<br/><br/>|{ 5853 }{ 585a }|
#586|<br/><br/>|{ 5863 }{ 586a }|
#222| = |{ 222a }{ 222b }|
#210| = |{ 210a }{ 210b }|
#024|<br/><br/><b>Standard No.: </b>|{ 024a }{ 024c }{ 024d }{ 0242 }|
#027|<br/><br/><b>Standard Tech. Report. No.: </b>|{ 027a }|
#028|<br/><br/><b>Publisher. No.: </b>|{ 028a }{ 028b }|
#013|<br/><br/><b>Patent No.: </b>|{ 013a }{ 013b }{ 013c }{ 013d }{ 013e }{ 013f }|
#030|<br/><br/><b>CODEN: </b>|{ 030a }|
#037|<br/><br/><b>Source: </b>|{ 037a }{ 037b }{ 037c }{ 037f }{ 037g }{ 037n }|
#010|<br/><br/><b>LCCN: </b>|{ 010a }|
#015|<br/><br/><b>Nat. Bib. No.: </b>|{ 015a }{ 0152 }|
#016|<br/><br/><b>Nat. Bib. Agency Control No.: </b>|{ 016a }{ 0162 }|
#600|<br/><br/><b>Персоналія--про людину: </b>|{\n6003 }{\n600a}{ 600b }{ 600c }{ 600d }{ 600e }{ 600f }{ 600g }{ 600h }{--600k}{ 600l }{ 600m }{ 600n }{ 600o }{--600p}{ 600r }{ 600s }{ 600t }{ 600u }{--600x}{--600z}{--600y}{--600v}|
#610|<br/><br/><b>Персоналія--Назва організації: </b>|{\n6103 }{\n610a}{ 610b }{ 610c }{ 610d }{ 610e }{ 610f }{ 610g }{ 610h }{--610k}{ 610l }{ 610m }{ 610n }{ 610o }{--610p}{ 610r }{ 610s }{ 610t }{ 610u }{--610x}{--610z}{--610y}{--610v}|
#611|<br/><br/><b>Персоналія--Назва зібрання: </b>|{\n6113 }{\n611a}{ 611b }{ 611c }{ 611d }{ 611e }{ 611f }{ 611g }{ 611h }{--611k}{ 611l }{ 611m }{ 611n }{ 611o }{--611p}{ 611r }{ 611s }{ 611t }{ 611u }{--611x}{--611z}{--611y}{--611v}|
#630|<br/><br/><b>Предмет--Уніфікована назва: </b>|{\n630a}{ 630b }{ 630c }{ 630d }{ 630e }{ 630f }{ 630g }{ 630h }{--630k }{ 630l }{ 630m }{ 630n }{ 630o }{--630p}{ 630r }{ 630s }{ 630t }{--630x}{--630z}{--630y}{--630v}|
#648|<br/><br/><b>Предмет--Хронологічний термін: </b>|{\n6483 }{\n648a }{--648x}{--648z}{--648y}{--648v}|
#650|<br/><br/><b>Предмет--Тематичний термін / MeSH: </b>|\n&emsp;{ 650a }{ 650b }{ 650c }{ 650d }{ 650e }{--650x}{--650z}{--650y}{--650v}|
#651|<br/><br/><b>Предмет--Географічний термін: </b>|{\n6513 }{\n651a}{ 651b }{ 651c }{ 651d }{ 651e }{--651x}{--651z}{--651y}{--651v}|
#653|<br/><br/><b>Предмет--Index Terms: </b>|{ 653a }|
#654|<br/><br/><b>Предмет--Facted Index Terms: </b>|{\n6543 }{\n654a}{--654b}{--654x}{--654z}{--654y}{--654v}|
#655|<br/><br/><b>Index Terms--Genre/Form: </b>|{\n6553 }{\n655a}{--655b}{--655x }{--655z}{--655y}{--655v}|
#656|<br/><br/><b>Index Terms--Occupation: </b>|{\n6563 }{\n656a}{--656k}{--656x}{--656z}{--656y}{--656v}|
#657|<br/><br/><b>Index Terms--Function: </b>|{\n6573 }{\n657a}{--657x}{--657z}{--657y}{--657v}|
#658|<br/><br/><b>Index Terms--Curriculum Objective: </b>|{\n658a}{--658b}{--658c}{--658d}{--658v}|
#080|<br/><br/><b>УДК: </b>|{ 080a }{ 080x }{ / 080b }|
#088|<br/><br/><b>Report. No.: </b>|{ 088a }|
ISBD

    # Значення за замовчуванням для ISBD (UNIMARC)
    my $default_unimarc = <<'ISBD';
#200||<font size="+1"><table width="100%" style="background:white;border:1;">|
#700||<tr><td colspan="2" width="100%" style="background:white;border:1;">|  
#942|      <b>|{942h}|</b><br/>
#942|      <b>|{942v}|</b><br/>
#700|      <b>|{700a}{, 700g }|</b>
#700||</td></tr>|
#200||<tr><td colspan="2" width="100%" style="background:white;border:1;">|  
#200|     |{200a}{ [200b] }{. 200c}{: 200e}{ = 200d}{. 200h}{. 200i}{ / 200f}{; 200g}|
#463| // |{463t}{ 463h} { 463v}{(463d)}|
#230||{; 230a}|
#205|. — |{; 205a}{, 205b}{ = 205d}{ / 205f}{; 205g}|
#210|. — |{; 210a}{ (210b) }{: 210c}{, 210d}|
#210|(|{ 210e}{(210f)}{: 210g}{, 210h}|)
#200h|. — |{200h}{ : 200i}|
#326a|. — |{326a}|
#215|. — |{; 215a}{: 215c}{; 215d}{ + 215e}|
#225|. — (|{ 225a}{ = 225d}{: 225e}{. 225h}{. 225i}{ / 225f}{, I225x}{; 225v}|)
#010|. — ISBN |{ 010a}{ (010b)}{: 010d}|
#200||</td></tr>|

#686|<tr style="background:white;border:1;"><td width="30%" style="background:white;border:1;"></td><td width="70%" style="background:white;border:1;"><b> |{6862 }{686a }|</b></td></tr>
#675|<tr style="background:white;border:1;"><td width="30%" style="background:white;border:1;"></td><td width="70%" style="background:white;border:1;"><b>УДК |{675a   }|</b></td></tr>

#606||<tr><td colspan="2" width="100%" style="background:white;border:1;">|
#606|<br/>     <font size="2"><thematic>|{- 606a }|</thematic></font>
#606||</td></tr>|

#995|<tr style="background:white;border:1;"><td style="background:white;border:1;" colspan="2"><table width="100%" style="background:white;border:1;"><tr style="background:white;border:1;"><td width="30%" style="background:white;border:1;"></td><td width="70%" style="background:white;border:1;"><font size="2"><block995>|{995c}{ — 995k}{ [995j]}<br/>|</block995></font></td></tr></table></td></tr>

#200||</table></font>|
ISBD

    $self->store_data({
        isbd_format_marc21  => $default_marc21,
        isbd_format_unimarc => $default_unimarc,
        enable_in_editor    => 0,
    });

    return 1;
}

sub uninstall {
    my ( $self, $args ) = @_;
    # При видаленні плагіна прибираємо внесені зміни з шаблону
    #$self->toggle_editor_toolbar(0);
    return 1;
}


# ##########################
# Хук Koha для вбудовування JS в штатну панель (IntranetUserJS)
# ##########################
sub intranet_js {
    my ( $self ) = @_;

    # Перевіряємо, чи увімкнено кнопку в налаштуваннях
    return '' unless $self->retrieve_data('enable_in_editor');

    my $js = <<'JS';
<script type="text/javascript">
$(document).ready(function() {
    // Шукаємо панель інструментів каталогізації (#toolbar)
    if ($("#toolbar").length) {
        console.log('Plugin:print_card. add buttons to toolbar');
        // Отримуємо biblionumber із URL
        var urlParams = new URLSearchParams(window.location.search);
        var urlPlugin = '/cgi-bin/koha/plugins/run.pl?class=Koha::Plugin::LibTeh::print_card';
        var biblionumber = urlParams.get('biblionumber');

        if (biblionumber && !$("#rtf-print-card-btn").length) {
            var rtfBlock = `
            <!-- ---------------------------------------
            Початок блоку друку карток у RTF
            --------------------------------------- -->
            <div id="rtf-print-card-btn" class="btn-group">
                <button type="button" class="btn btn-default dropdown-toggle" data-bs-toggle="dropdown" aria-haspopup="true" aria-expanded="false">
                    <i class="fa fa-print"></i> Друк документів (RTF)
                </button>
                <ul class="dropdown-menu">
                    <li><a class="dropdown-item" href="${urlPlugin}&method=tool&op=primary_card&biblionumber=${biblionumber}"> Основна картка </a></li>
                    <li><a class="dropdown-item" href="${urlPlugin}&method=tool&op=reverse_card&biblionumber=${biblionumber}"> Оборот картки </a></li>
                    <li><a class="dropdown-item" href="${urlPlugin}&method=tool&op=topological_card&biblionumber=${biblionumber}"> Топокартка </a></li>
                    <li><a class="dropdown-item" href="${urlPlugin}&method=tool&op=form&biblionumber=${biblionumber}"> Формуляр </a></li>
                </ul>
            </div>
            <!-- ---------------------------------------
            Кінець блоку друку карток у RTF
            --------------------------------------- -->`;

            // Якщо є випадаюче меню "Додати до списку" або VirtualShelves — вставляємо ПЕРЕД ним
            var target = $("#addtoshelf").closest(".btn-group");
            
            if (target.length) {
                target.before(rtfBlock);
            } else {
                // Якщо елемента немає, додаємо в кінець панелі
                $("#toolbar").append(rtfBlock);
            }
        }
    }
});
</script>
JS

    return $js;
}


## This method allows you to add new html elements to the catalogue toolbar.
## You'll want to return a string of raw html here, most likely a button or other
## toolbar element of some form. See bug 20968 for more details.
sub intranet_catalog_biblio_enhancements_toolbar_button {
    my ( $self ) = @_;

    return q|
        <a class="btn btn-default" role="button" tabindex="0" onclick="alert('Peace and long life');">
          <i class="fa fa-hand-spock" aria-hidden="true"></i>
          Live long and prosper
        </a>
    |;
}


# ##########################
# Сторінка налаштувань (кнопка Налаштування)
# ##########################
sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    if ( $cgi->param('cud-save') ) {
        my $isbd_marc21  = $cgi->param('isbd_format_marc21') // '';
        my $isbd_unimarc = $cgi->param('isbd_format_unimarc') // '';
        my $in_editor    = $cgi->param('enable_in_editor') ? 1 : 0;

        $self->store_data({
            isbd_format_marc21  => $isbd_marc21,
            isbd_format_unimarc => $isbd_unimarc,
            enable_in_editor    => $in_editor,
        });

        # Модифікуємо або очищуємо cat-toolbar.inc залежно від стану перемикача
        #$self->toggle_editor_toolbar($in_editor);

        print $cgi->redirect( -url => '/cgi-bin/koha/plugins/run.pl?class=' . ref($self) . '&method=configure&saved=1' );
        return;
    }

    my $template = $self->get_template({ file => 'templates/configure.tt' });
    $template->param(
        isbd_format_marc21  => $self->retrieve_data('isbd_format_marc21'),
        isbd_format_unimarc => $self->retrieve_data('isbd_format_unimarc'),
        enable_in_editor    => $self->retrieve_data('enable_in_editor'),
        saved               => $cgi->param('saved') // 0,
    );

    print $cgi->header( -type => 'text/html', -charset => 'utf-8' );
    print $template->output();
}


# ##########################
# Основний керуючий блок
# ##########################
sub tool {
    my ( $self, $args ) = @_;
    my $cgi             = $self->{'cgi'};
    my $biblionumber    = $cgi->param('biblionumber');
    my $op              = $cgi->param('op');
    $biblionumber = HTML::Entities::encode($biblionumber);
    
    if ($biblionumber) {
        if ($op eq 'primary_card'){
            $self->print_primary_card($biblionumber);
        }elsif($op eq 'reverse_card'){
            $self->print_reverse_card($biblionumber);
        }elsif($op eq 'topological_card'){
            $self->print_topological_card($biblionumber);
        }elsif($op eq 'form'){
            $self->print_form($biblionumber);
        }
    } else {
        print $cgi->header( -type => 'text/html', -charset => 'utf-8' );
        print "<h3>Помилка: не вказано biblionumber</h3>";
    }
}


# ##########################
# Друк основної картки
# ##########################
sub print_primary_card {
    my ( $self, $biblionumber ) = @_;
    my $cgi                     = $self->{'cgi'};
    my $biblio                  = Koha::Biblios->find($biblionumber);
    my $format                  = lc( C4::Context->preference('marcflavour') // 'marc21' );
    
    unless ($biblio) {
        print $cgi->header( -type => 'text/html', -charset => 'utf-8' );
        print "<h3>Запис з ID $biblionumber не знайдено</h3>";
        return;
    }

    my $record    = $biblio->metadata_record( { embed_items => 1, interface => 'intranet' } );
    my $framework = $biblio->frameworkcode;

    # Зчитуємо шаблони із налаштувань плагіна
    my $isbd_format;
    if ($format eq 'unimarc') {
        $isbd_format = $self->retrieve_data('isbd_format_unimarc');
    } else {
        $isbd_format = $self->retrieve_data('isbd_format_marc21');
    }

    my $ISBDView = GetISBDViewAddon(
        {
            'record'      => $record,
            'template'    => 'intranet',
            'framework'   => $framework,
            'isbd_format' => $isbd_format,
        }
    );

    my $print_text_start = "{\\rtf1\\ansi\\ansicpg1251\\deff0\\deflang1049{\\fonttbl{\\f0\\fnil\\fcharset204 Arial;}}"
                         . "\\viewkind4\\uc1\\pard\\f0\\fs14\\paperw7086\\paperh4552\\margl567\\margr567\\margt567\\margb567";

    my $print_text_end = "\\par}";

    my $res_rtf = HTML::FormatRTF->format_string($ISBDView);
    $res_rtf =~ s/\{\\header.*?\\chpgn\\par\}//gs;

# ========================
#    warn "DEBUG ISBDView: " . Dumper($ISBDView);
# ========================
    my $print_text = $print_text_start . $res_rtf . $print_text_end;
    $print_text = encode('cp1251', $print_text, Encode::FB_DEFAULT);

    print $cgi->header(
        -type                   => 'application/rtf',
        -charset                => 'windows-1251',
        -attachment             => "card_$biblionumber.rtf",
        -Content_Length         => length($print_text),
        -Access_Control_Allow_Origin => '*'
    );
    print $print_text;
    exit;
}


# ##########################
# Друк обороту картки
# ##########################
sub print_reverse_card{
    
}


# ##########################
# Друк топологічної картки
# ##########################
sub print_topological_card{
    
}


# ##########################
# Друк формуляра
# ##########################
sub print_form{
    
    my ( $self, $biblionumber ) = @_;
    my $cgi                     = $self->{'cgi'};
    my $biblio                  = Koha::Biblios->find($biblionumber);
    my $format                  = lc( C4::Context->preference('marcflavour') // 'marc21' );
    
    my $RTF_HEADER              = <<~'CARD_RTF_HEADER';
    {\rtf1\ansi\ansicpg1252\deff0\nouicompat\deflang1033\deflangfe1033\deftab708{\fonttbl{\f0\froman\fprq2\fcharset0 Times New Roman;}{\f1\fswiss\fprq2\fcharset0 Calibri;}}
    {\*\generator Riched20 10.0.19041}{\*\mmathPr\mnaryLim0\mdispDef1\mwrapIndent1440 }\viewkind4\paperw3686\paperh5670\margl284\margr851\margt284\margb284\uc1
    CARD_RTF_HEADER

    my $RTF_BODY                = <<~'CARD_RTF_BODY';
    \trowd\trgaph108\trleft-108\trbrdrl\brdrs\brdrw10 \trbrdrt\brdrs\brdrw10 \trbrdrr\brdrs\brdrw15 \trbrdrb\brdrs\brdrw10 \trpaddl108\trpaddr108\trpaddfl3\trpaddfr3
    \clbrdrl\brdrw10\brdrs\clbrdrt\brdrw10\brdrs\clbrdrr\brdrw10\brdrs\clbrdrb\brdrw15\brdrs \cellx3119 
    \pard\intbl\widctlpar\f1\fs22 ###INV_NUMBER###\cell\row\trowd\trgaph108\trleft-108\trbrdrl\brdrs\brdrw10 \trbrdrt\brdrs\brdrw10 \trbrdrr\brdrs\brdrw15 \trbrdrb\brdrs\brdrw10 \trpaddl108\trpaddr108\trpaddfl3\trpaddfr3
    \clbrdrl\brdrw10\brdrs\clbrdrt\brdrw15\brdrs\clbrdrr\brdrw10\brdrs\clbrdrb\brdrw15\brdrs \cellx3119 
    \pard\intbl\widctlpar ###SHIFR###\cell\row\trowd\trgaph108\trleft-108\trbrdrl\brdrs\brdrw10 \trbrdrt\brdrs\brdrw10 \trbrdrr\brdrs\brdrw15 \trbrdrb\brdrs\brdrw10 \trpaddl108\trpaddr108\trpaddfl3\trpaddfr3
    \clbrdrl\brdrw10\brdrs\clbrdrt\brdrw15\brdrs\clbrdrr\brdrw10\brdrs\clbrdrb\brdrw15\brdrs \cellx3119 
    \pard\intbl\widctlpar ###AUTHOR_CODE###\cell\row\trowd\trgaph108\trleft-108\trbrdrl\brdrs\brdrw10 \trbrdrt\brdrs\brdrw10 \trbrdrr\brdrs\brdrw15 \trbrdrb\brdrs\brdrw10 \trpaddl108\trpaddr108\trpaddfl3\trpaddfr3
    \clbrdrl\brdrw10\brdrs\clbrdrt\brdrw15\brdrs\clbrdrr\brdrw10\brdrs\clbrdrb\brdrw15\brdrs \cellx3119 
    \pard\intbl\widctlpar ###BO###\cell\row\trowd\trgaph108\trleft-108\trbrdrl\brdrs\brdrw10 \trbrdrt\brdrs\brdrw10 \trbrdrr\brdrs\brdrw15 \trbrdrb\brdrs\brdrw10 \trpaddl108\trpaddr108\trpaddfl3\trpaddfr3
    \clbrdrl\brdrw10\brdrs\clbrdrt\brdrw15\brdrs\clbrdrr\brdrw15\brdrs\clbrdrb\brdrw10\brdrs \cellx1560\clbrdrl\brdrw15\brdrs\clbrdrt\brdrw15\brdrs\clbrdrr\brdrw10\brdrs\clbrdrb\brdrw10\brdrs \cellx3119 
    \pard\intbl\widctlpar ###YEAR###\cell ###PRICE###\cell\row 
    CARD_RTF_BODY

    my $RTF_FOOTER              = <<~'CARD_RTF_FOOTER';
    \pard\widctlpar\sa200\sl276\slmult1\par 
    }
    CARD_RTF_FOOTER

    my $print_text              = '';
    my $record_marc             = $biblio->metadata->record;
    my $BO                      = ($format eq 'unimarc') ? $record_marc->field('200')->subfield('a') : $record_marc->field('245')->subfield('a');
    $BO                         =~ s/([^[:ascii:]])/sprintf("\\u%d\\'5f",ord($1))/eg;
    my $YEAR                    = ($format eq 'unimarc') ? $record_marc->field('210')->subfield('d') : $record_marc->field('260')->subfield('c') ;                   
    my $items                   = $biblio->items;
    my $number                  = 0;
    while ( my $item = $items->next ) {
        my $template            = $RTF_BODY;
        my $INV_NUMBER          = $item->stocknumber;
        my $SHIFR               = $item->itemcallnumber;
        $SHIFR                  =~ s/([^[:ascii:]])/sprintf("\\u%d\\'5f",ord($1))/eg;
        my $AUTHOR_CODE         = '';
        my $PRICE               = $item->price;
        $template               =~ s/###INV_NUMBER###/$INV_NUMBER/;                   
        $template               =~ s/###SHIFR###/$SHIFR/;   
        $template               =~ s/###AUTHOR_CODE###/$AUTHOR_CODE/;   
        $template               =~ s/###BO###/$BO/;   
        $template               =~ s/###YEAR###/$YEAR/;   
        $template               =~ s/###PRICE###/$PRICE/;
        $print_text            .= $template . '\pard \ltrpar \ql \li0\ri0\sa200\sl276\slmult1\widctlpar\wrapdefault\aspalpha\aspnum\faauto\adjustright\rin0\lin0\itap0 {\rtlch\fcs1 \af31507 \ltrch\fcs0 \insrsid1330454 \page \par \ltrrow}';
    }

    print $cgi->header(
        -type       => 'application/octet-stream',
        -charset    => 'utf-8',
        -attachment => "formular_$biblionumber.rtf"
    );
    print $RTF_HEADER . $print_text . $RTF_FOOTER;
        
}


# ##########################
# 
# ##########################
sub GetISBDViewAddon {
    my ($params) = @_;

    my $record = $params->{record};
    return unless defined $record;

    my $template    = $params->{template} // q{};
    my $framework   = $params->{framework} // '';
    my ( $holdingbrtagf, $holdingbrtagsubf ) = GetMarcFromKohaField("items.holdingbranch");
    my $tagslib = GetMarcStructure( 1, $framework, { unsafe => 1 } );

    my $block = $params->{isbd_format} // q{};
    my $res = '';

    foreach my $isbdfield ( split( /#/, $block ) ) {
        next unless $isbdfield;

        unless ( $isbdfield =~ /^(\d{3})([^\|])?\|(.*)\|(.*)\|(.*)$/s ) {
            $res .= $isbdfield;
            next;
        }

        my $fieldvalue    = $1;
        my $subfvalue     = $2 // "";
        my $textbefore    = $3 // "";
        my $analysestring = $4 // "";
        my $textafter     = $5 // "";

        my $hasputtextbefore = 0;
        my $blocres = '';
        my @fieldslist = $record->field($fieldvalue);

        if ( $holdingbrtagf && $fieldvalue eq $holdingbrtagf ) {
            @fieldslist = sort { ($a->subfield($holdingbrtagsubf) // '') cmp ($b->subfield($holdingbrtagsubf) // '') } @fieldslist;
        }

        if ( $subfvalue ne "" ) {
            next if ( $template eq 'opac' && ( $tagslib->{$fieldvalue}->{$subfvalue}->{'hidden'} || 0 ) > 0 );

            foreach my $field (@fieldslist) {
                foreach my $subfield ( $field->subfield($subfvalue) ) {
                    next unless defined $subfield;

                    my $calculated = $analysestring;
                    my $tag = $field->tag();

                    if ( $tag >= 10 ) {
                        my $subfieldvalue = GetAuthorisedValueDesc( $tag, $subfvalue, $subfield, '', $tagslib ) // $subfield;
                        my $tagsubf = $tag . $subfvalue;

                        $calculated =~ s/\{([^{}]*?)\Q$tagsubf\E([^{}]*?)\}/$1$subfieldvalue$2/g;

                        if ( $template eq "opac" ) {
                            $calculated =~ s#/cgi-bin/koha/[^/]+/([^.]*\.pl\?.*)$#opac-$1#g;
                        }

                        if ( $calculated && !$hasputtextbefore ) {
                            $blocres .= $textbefore;
                            $hasputtextbefore = 1;
                        }

                        $calculated =~ s/^( |;|:|\.|-)*//g;
                        $blocres .= $calculated;
                    }
                }
            }
            $blocres .= $textafter if $hasputtextbefore;
        } else {
            foreach my $field (@fieldslist) {
                my $calculated = $analysestring;
                my $tag = $field->tag();

                if ( $tag >= 10 ) {
                    my @subf = $field->subfields;
                    for my $i ( 0 .. $#subf ) {
                        my $subfieldcode = $subf[$i][0];
                        my $valuecode    = $subf[$i][1];

                        next if ( $template eq 'opac' && ( $tagslib->{$fieldvalue}->{$subfieldcode}->{'hidden'} || 0 ) > 0 );

                        my $subfieldvalue = GetAuthorisedValueDesc( $tag, $subfieldcode, $valuecode, '', $tagslib ) // $valuecode;
                        my $tagsubf = $tag . $subfieldcode;

                        $calculated =~ s/\{\{\Q$tagsubf\E\}\}/$valuecode/g;
                        $calculated =~ s/\{([^{}]*?)\Q$tagsubf\E([^{}]*?)\}/$1$subfieldvalue$2/g;

                        if ( $template eq "opac" ) {
                            $calculated =~ s#/cgi-bin/koha/[^/]+/([^.]*\.pl\?.*)$#opac-$1#g;
                        }
                    }

                    if ( $calculated && !$hasputtextbefore ) {
                        $blocres .= $textbefore;
                        $hasputtextbefore = 1;
                    }

                    $calculated =~ s/^( |;|:|\.|-)*//g;
                    $blocres .= $calculated;
                }
            }
            $blocres .= $textafter if $hasputtextbefore;
        }
        $res .= $blocres;
    }

    $res =~ s/\{[^{}]*\}//g;
    $res =~ s/\\n/\n/g;
    $res =~ s/\n/<br\/>/g;
    $res =~ s/\(\)//g;

    return $res;
}

1;