while(my $line = <>) {
    chomp($line);
    my @split = (split(/:/, $line))[0, 2, 1, 5];
    my $string = join("\t", @split);
    print $string, "\n"
}