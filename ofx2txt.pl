#!/usr/bin/perl
use warnings FATAL => 'all';
use strict;
use Date::Manip;

my $TZ_ABBR =
"(ADT|AFT|AKDT|AKST|ALMT|AMST|AMT|ANAST|ANAT|AQTT|ART|AST|AZOST|AZOT|AZST|AZT|\
BNT|BOT|BRST|BRT|BST|BTT|CAST|CAT|CCT|CDT|CEST|CET|CHADT|CHAST|ChST|CKT|CLST|\
CLT|COT|CST|CVT|CXT|DAVT|EASST|EAST|EAT|ECT|EDT|EEST|EET|EGST|EGT|EST|ET|FJST|\
FJT|FKST|FKT|FNT|GALT|GAMT|GET|GFT|GILT|GMT|GST|GYT|HAA|HAC|HADT|HAE|HAP|HAR|\
HAST|HAT|HAY|HKT|HLV|HNA|HNC|HNE|HNP|HNR|HNT|HNY|HOVT|ICT|IDT|IOT|IRDT|IRKST|\
IRKT|IRST|IST|JST|KGT|KRAST|KRAT|KST|KUYT|LHDT|LHST|LINT|MAGST|MAGT|MART|MAWT|\
MDT|MESZ|MEZ|MHT|MMT|MSD|MSK|MST|MUT|MVT|MYT|NCT|NDT|NFT|NOVST|NOVT|NPT|NST|\
NUT|NZDT|NZST|OMSST|OMST|PDT|PET|PETST|PETT|PGT|PHOT|PHT|PKT|PMDT|PMST|PONT|\
PST|PT|PWT|PYST|PYT|RET|SAMT|SAST|SBT|SCT|SGT|SRT|SST|TAHT|TFT|TJT|TKT|TLT|\
TMT|TVT|ULAT|UYST|UYT|UZT|VET|VLAST|VLAT|VUT|WAST|WAT|WDT|WEST|WESZ|WET|WEZ|\
WFT|WGST|WGT|WIB|WIT|WITA|WST|WT|YAKST|YAKT|YAPT|YEKST|YEKT)";
my $TZ_REX = qr/ $TZ_ABBR|$TZ_ABBR /i;

my $OFX_ENTRY_PREFIX = "ofx_proc_";
my $OFX_KEYS = { # if the value is 0, those fields will not be processed
    account => {
        "Account ID"                                      => {
            new_key          => "id",
            value_parse_func => \&field_parse
        },
        "Account type"                                    => {
            new_key          => "type",
            value_parse_func => \&field_parse
        },
        "Account #"                                       => {
            new_key          => "number",
            value_parse_func => \&field_parse
        },
        "Account name"                                    => 0,
        "Currency"                                        => 0
    },
    statement => {
        "Account ID"                                      => {
            new_key          => "account_id",
            value_parse_func => \&field_parse
        },
        "Start date of this statement"                    => {
            new_key          => "start_date",
            value_parse_func => \&date_parse_naive
        },
        "End date of this statement"                      => {
            new_key          => "end_date",
            value_parse_func => \&date_parse_naive
        },
        "Ledger balance"                                  => {
            new_key          => "balance",
            value_parse_func => \&field_parse
        },
        "Currency"                                        => 0
    },
    transaction => {
        "Financial institution's ID for this transaction" => {
            new_key          => "id",
            value_parse_func => \&field_parse
        },
        "Account ID"                                      => {
            new_key          => "account_id",
            value_parse_func => \&field_parse
        },
        "Date posted"                                     => {
            new_key          => "date",
            value_parse_func => \&date_parse_naive
        },
        "Transaction type"                                => {
            new_key          => "type",
            value_parse_func => \&type_parse
        },
        "Total money amount"                              => {
            new_key          => "amount",
            value_parse_func => \&field_parse
        },
        "Name of payee or transaction description"        => {
            new_key          => "description",
            value_parse_func => \&field_parse
        },
        "# of units"                                      => 0,
        "Unit price"                                      => 0
    }
};

my $PRINT_ORDER = {
    account     => {
        id          => 0,
        type        => 1,
        number      => 2,
    },
    statement   => {
        account_id  => 0,
        start_date  => 1,
        end_date    => 2,
        balance     => 3
    },
    transaction => {
        id          => 0,
        account_id  => 1,
        date        => 2,
        type        => 3,
        amount      => 4,
        description => 5
    }
};

my $MONTH = {
    Jan => 1,
    Feb => 2,
    Mar => 3,
    Apr => 4,
    May => 5,
    Jun => 6,
    Jul => 7,
    Aug => 8,
    Sep => 9,
    Oct => 10,
    Nov => 11,
    Dec => 12
};

my @files = @ARGV;

sub print_fields()
{
    my $fields     = shift;
    my $first_time = 1;

    for my $field (@$fields) {
        $first_time ? $first_time = 0 : print '|';
        print "$field";
    }
    print "\n";
}

sub field_parse()
{
    my $value = shift;
    return $value;
}

# This functions is a huge bottleneck. Just creating date object
# takes a fair bit of time.
sub date_parse_slow()
{
    my $date_str = shift;
    my $date     = new Date::Manip::Date;
    my $err      = 1;

    $date_str =~ s/$TZ_REX//;
    $err = $date->parse($date_str);

    if($err) {
        print "$err\n";
        die($date->err($err));
    }

    $date_str = $date->printf("%m%d%y");
    return $date_str;
}

# Assumes format: Tue Feb 14 11:00:00 2012 CST
sub date_parse_naive()
{
    my $date_str = shift;
    my @fields   = split(/ /, $date_str);
    my $month    = 0;
    my $day      = $fields[2];
    my $year     = $fields[4];
    my $new_str  = "";

    unless(exists $MONTH->{$fields[1]} && defined $MONTH->{$fields[1]}) {
        die("Invalid month; date format changed?");
    }

    # If this program is still being used in the year 2100 ... OH MY!
    unless(2000 < $year && $year < 2099) {
        die("Unexpected year; date format changed?");
    }

    unless(0 < $day && $day <= 31) {
        die("Invalid day; date format changed?");
    }

    $month = $MONTH->{$fields[1]};
    $new_str = sprintf("%04d%02d%02d", $year, $month, $day);
    return $new_str;
}

sub type_parse()
{
    my $type   = shift;
    my @parsed = split(/:/,$type,2);

    if("" eq $parsed[0]) {
        die("Unexpected type; type format changed?");
    }

    return $parsed[0];
}

sub trim()
{
    my $str = shift;
    $str =~ s/[\s]+/ /g;
    $str =~ s/^ //;
    $str =~ s/ $//;
    return $str;
}

sub parse_line()
{
    my $new_entry  = shift;
    my $line       = shift;
    my $entry_list = shift;
    my $ofx_keys   = shift;

    if($line =~ '^\s*$') {
        return;
    }

    my @fields     = ();
    my $entry      = $new_entry ? {} : pop(@$entry_list);
    my $num_fields = 0;
    my $new_key    = "";
    my $parse_func = "";
    my $field_hash = "";
    my $order      = "";
    chomp($line);

    @fields = split(/[:]/,$line, 2);

    $num_fields = @fields;
    for(my $i = 0; $i < $num_fields; ++$i) {
        $fields[$i] = &trim($fields[$i]);
    }

    if(exists($ofx_keys->{ $fields[0] }) &&
      defined($ofx_keys->{ $fields[0] }) &&
      $ofx_keys->{ $fields[0] }) {
        $new_key    = $ofx_keys->{ $fields[0] }->{ 'new_key' };
        $parse_func = $ofx_keys->{ $fields[0] }->{ 'value_parse_func' };
        $order      = $ofx_keys->{ $fields[0] }->{ 'order' };
        $entry->{ $new_key } = $parse_func->($fields[1]);
    }

    push(@$entry_list, $entry);
}

sub parse_file()
{
    my $filename   = shift;
    my $entries    = shift;
    my @lines      = `ofxdump $filename 2>>ofx.log`;
    my $num_lines  = @lines;
    my $line_num   = 0;
    my $new_entry  = 0;
    my $type       = "";
    my $fields     = "";

    # State A: Find next handled entry for processing
    find_next:
        goto terminate if($line_num >= $num_lines);

        if($lines[$line_num] =~ "^$OFX_ENTRY_PREFIX([^(]+)") {
            $type = $1;
            ++$line_num;
            goto find_next unless(defined($OFX_KEYS->{ $type }));
            $new_entry = 1;
            goto proc_line;
        }

        ++$line_num;
        goto find_next;

    # State B: Process handled entry
    proc_line:
        goto terminate if($line_num >= $num_lines);

        if($lines[$line_num] =~ "^$OFX_ENTRY_PREFIX") {
            goto find_next;
        }

        &parse_line($new_entry       , $lines[$line_num],
                    $entries->{$type}, $OFX_KEYS->{$type});

        ++$line_num;
        $new_entry = 0;
        goto proc_line;

    # State Z: All entries processed, exit
    terminate:
        return;
}

sub entries_to_list()
{
    my $type    = shift;
    my $order   = shift;
    my $entries = shift;
    my $list    = ();

    # each entry for given type
    for my $entry (@$entries) {
        my $full_entry = "";
        $full_entry .= sprintf("%s", $type);
        for my $key (sort {$order->{$a} <=> $order->{$b}} (keys(%$entry))) {
            $full_entry .= sprintf("|%s", $entry->{ $key });
        }
        push(@$list, $full_entry);
    }
    return $list;
}

sub test()
{
    my $files       = shift;
    my $entries     = shift;
    my $contents    = "";
    my @entry_types = keys %$entries;
    my $die_format  =
        "Number of %s(s) in file(s) is %s than total parsed (%d %s %d).\n";

    for my $file (@$files) {
        $contents .= `ofxdump $file 2>>ofx.log`;
    }

    for my $type (@entry_types) {
        my $count1 = 0;
        my $count2 = 0;
        my $order  = $PRINT_ORDER->{ $type };
        my $parsed = &entries_to_list($type, $order, $entries->{$type});

        ++$count1 while($contents =~ m/^$OFX_ENTRY_PREFIX$type/msg);

        for my $entry (@$parsed) {
            ++$count2 if($entry =~ m/^$type\|/msg);
        }

        if($count1 > $count2) {
            my $die_msg =
                sprintf($die_format, $type, "more", $count1, ">", $count2);
            die($die_msg);
        }
        if($count1 < $count2) {
            my $die_msg =
                sprintf($die_format, $type, "less", $count1, "<", $count2);
            die($die_msg);
        }
    }
}

sub uniq()
{
    my $list = shift;
    my %seen = ();
    my @uniq = ();

    for my $item (@$list) {
        unless($seen{$item}) {
            $seen{$item} = 1;
            push(@uniq, $item);
        }
    }
    $list = \@uniq;

}

sub sanitize_filenames()
{
    my $ifiles = shift;
    my $ofiles = ();

    for my $file (@$ifiles) {
        if($file =~ m/^[a-zA-Z0-9_.\/-]+$/) {
            push(@$ofiles, $file);
        }
        else {
            print STDERR "Filename '$file' not supported; skipping.\n";
            print STDERR "Supported characters: 'a-zA-Z0-9_.-'.\n\n";
        }
    }

    return $ofiles;
}

# Transactions are only unique per account. The account id needs to be appended
# to help enforce uniqueness of transaction ids across all accounts.
# REFACTOR: This function and the call to it are not as general as the rest of
# the application and should be refactored.
sub make_trans_id_uniq()
{
    my $entries = shift;

    for my $entry (@$entries) {
        $entry->{'id'} .= ' ' . $entry->{'account_id'};
    }
}

sub main()
{
    my $files  = shift;
    my %entries = (); # type => list of hash tables (each making up an entry)

    $files = &sanitize_filenames($files);

    for my $type (keys %$OFX_KEYS)  {
        $entries{ $type } = [];
    }

    for my $file (@$files) {
        &parse_file($file, \%entries);
    }

    &make_trans_id_uniq($entries{'transaction'});

    while(my ($type, $entry_list) = each(%entries)) {
        # print output format as comment for each type
        print "# table";
        my $order = $PRINT_ORDER->{ $type };
        for my $column (sort {$order->{$a} <=> $order->{$b}} keys %$order) {
            print "|$column";
        }
        print "\n";

        my $unique = &uniq(&entries_to_list($type, $order, $entry_list));
        for my $entry (@$unique) {
            print "$entry\n";
        }
    }

    &test($files, \%entries);
}

&main(\@files);

exit 0;
