#!/usr/bin/perl
use warnings FATAL => 'all';
use strict;
use Getopt::Long;

my $OFX_ENTRY_PREFIX = "ofx_proc_";
my $OFX_KEYS = { # if the value is 0, those fields will not be processed
    account => {
        "Account ID"                                      => {
            new_key          => "id",
            value_parse_func => \&foo
        },
        "Account type"                                    => {
            new_key          => "type",
            value_parse_func => \&foo
        },
        "Account #"                                       => {
            new_key          => "number",
            value_parse_func => \&foo
        },
        "Bank ID"                                         => {
            new_key          => "bank_id",
            value_parse_func => \&foo
        },
        "Account name"                                    => 0,
        "Currency"                                        => 0
    },
    statement => {
        "Account ID"                                      => {
            new_key          => "account_id",
            value_parse_func => \&foo
        },
        "Start date of this statement"                    => {
            new_key          => "start_date",
            value_parse_func => \&foo
        },
        "End date of this statement"                      => {
            new_key          => "end_date",
            value_parse_func => \&foo
        },
        "Ledger balance"                                  => {
            new_key          => "balance",
            value_parse_func => \&foo
        },
        "Currency"                                        => 0
    },
    transaction => {
        "Financial institution's ID for this transaction" => {
            new_key          => "id",
            value_parse_func => \&foo
        },
        "Account ID"                                      => {
            new_key          => "account_id",
            value_parse_func => \&foo
        },
        "Date posted"                                     => {
            new_key          => "date",
            value_parse_func => \&foo
        },
        "Transaction type"                                => {
            new_key          => "type",
            value_parse_func => \&foo
        },
        "Total money amount"                              => {
            new_key          => "amount",
            value_parse_func => \&foo
        },
        "Name of payee or transaction description"        => {
            new_key          => "description",
            value_parse_func => \&foo
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
        bank_id     => 3
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

my @files = ();
my $options = GetOptions (
    "f|file=s" => \@files,
    "h|help"   => \(my $help)
);

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

sub foo()
{
    my $value = shift;
    return $value;
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
    my @lines      = `ofxdump $filename`;
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

sub unique_entries_as_text()
{
    my $type    = shift;
    my $order   = shift;
    my $entries = shift;
    my $text    = "";

    # print each entry for given type
    for my $entry (@$entries) {
        $text .= sprintf("%s", $type);
        for my $key (sort {$order->{$a} <=> $order->{$b}} (keys(%$entry))) {
            $text .= sprintf("|%s", $entry->{ $key });
        }
        $text .= sprintf("\n");
    }
    return $text;
}

sub test()
{
    my $files       = shift;
    my $entries     = shift;
    my $contents    = "";
    my @entry_types = keys %$entries;

    for my $file (@$files) {
        $contents .= `ofxdump $file`;
    }

    for my $type (@entry_types) {
        my $count1 = 0;
        my $count2 = 0;
        my $order  = $PRINT_ORDER->{ $type };
        my $parsed = &unique_entries_as_text($type, $order, $entries->{$type});

        ++$count1 while($contents =~ m/^$OFX_ENTRY_PREFIX$type/msg);
        ++$count2 while($parsed   =~ m/^$type\|/msg);

        if($count1 > $count2) {
            die("Number of $type(s) in file(s) is more than total parsed.\n");
        }
        if($count1 < $count2) {
            die("Number of $type(s) in file(s) is less than total parsed.\n");
        }
    }

}

sub main()
{
    my $files   = shift;
    my %entries = ();

    for my $type (keys %$OFX_KEYS)  {
        $entries{ $type } = [];
    }

    for my $file (@$files) {
        &parse_file($file, \%entries);
    }

    while(my ($type, $entry_list) = each(%entries)) {
        # print output format as comment for each type
        print "# table";
        my $order = $PRINT_ORDER->{ $type };
        for my $column (sort {$order->{$a} <=> $order->{$b}} keys %$order) {
            print "|$column";
        }
        print "\n";

        print &unique_entries_as_text($type, $order, $entry_list);
    }

    &test($files, \%entries);
}

&main(\@files);

exit 0;
