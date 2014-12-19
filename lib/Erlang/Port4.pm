## ----------------------------------------------------------------------------
#  Erlang::Port4.
# -----------------------------------------------------------------------------
# Mastering programmed by YAMASHINA Hio
#
# Copyright 2007 YAMASHINA Hio
# -----------------------------------------------------------------------------
# $Id: /perl/Erlang-Port4/lib/Erlang/Port4.pm 388 2007-05-22T11:24:11.684354Z hio  $
# -----------------------------------------------------------------------------
package Erlang::Port4;
use strict;
use warnings;

our $VERSION = '0.04';

# constans.
our $SMALL_INTEGER_EXT = 'a';
our $INTEGER_EXT       = 'b';
our $FLOAT_EXT         = 'c';
our $ATOM_EXT          = 'd';
our $REFERENCE_EXT     = 'e';
our $NEW_REFERENCE_EXT = 'r';
our $PORT_EXT          = 'f';
our $PID_EXT           = 'g';
our $SMALL_TUPLE_EXT   = 'h';
our $LARGE_TUPLE_EXT   = 'i';
our $NIL_EXT           = 'j';
our $STRING_EXT        = 'k';
our $LIST_EXT          = 'l';
our $BINARY_EXT        = 'm';
our $BIT_BINARY_EXT    = 'M';
our $SMALL_BIG_EXT     = 'n';
our $LARGE_BIG_EXT     = 'o';
our $NEW_FUN_EXT       = 'p';
our $EXPORT_EXT        = 'q';
our $FUN_EXT           = 'u';

our $NEW_CACHE         = 'N';
our $CACHED_ATOM       = 'C';

our $COMPRESSED        = 'P';
our $VERSION_MAGIC     = pack('C',131);   # 130 in erlang 4.2.

1;

# -----------------------------------------------------------------------------
# $pkg->new(\&callback);
#
sub new
{
	my $pkg = shift;
	my $callback = shift;
	
	my $this = bless {}, $pkg;
	$this->{callback} = $callback;
	if( 0 )
	{
		my $logfile = 'port.out';
		open(my$out, '>>', $logfile) or die "$logfile: $!";
		select((select($out),$|=1)[0]);
		print $out "start: $$, ".localtime(time)."\r\n";
		$this->{log} = $out;
	}
	$this;
}

# -----------------------------------------------------------------------------
# dtor.
#
sub DESTROY
{
	my $this = shift;
	if( my $out = $this->{log} )
	{
		print $out "end: $$, ".localtime(time)."\r\n";
	}
}

# -----------------------------------------------------------------------------
# $port->loop().
#
sub loop()
{
	my $this = shift;
	
	binmode(STDOUT);
	$|=1;
	for(;;)
	{
		my $cmd = $this->_read_cmd();
		my $obj = $this->decode($cmd);
		my $ret = $this->{callback}->($obj, $this);
		my $bin = $this->encode($ret);
		print pack("N",length($bin)).$bin;
	}
}

# -----------------------------------------------------------------------------
# $port->_read_cmd() @ private.
#  read erlang external command.
#
sub _read_cmd
{
	my $this = shift;
	my $out = $this->{log};
	
	$out and print $out "read cmd ...\r\n";
	my $len = $this->_read_exact(4);
	$len = unpack("N", $len);
	$out and print $out "read cmd, len = $len ...\r\n";
	my $data = $this->_read_exact($len);
	my $x = $data;
	$x =~ s/([^ -~])/sprintf('[%02d]',unpack("C",$1))/eg;
	$out and print $out "read cmd, data($len) = $x ...\r\n";
	$data;
}

# -----------------------------------------------------------------------------
# $port->_read_exact($len) @ private.
#  read $len bytes.
#
sub _read_exact
{
	my $this = shift;
	my $out = $this->{log};
	
	my $len = shift;
	my $buf = '';
	for(1..$len)
	{
		my $ret = read(STDIN, $buf, 1, length $buf);
		if( !defined($ret) )
		{
			$out and print $out "sysread: $!\r\n";
			exit -1;
		}
		if( !$ret )
		{
			$out and print $out "EOF.\r\n";
			exit 0;
		}
		$out and print $out ">> $_ ".sprintf('[%02d]',unpack("C",substr($buf,-1)))."\r\n";
	}
	$buf;
}

# -----------------------------------------------------------------------------
# $port->decode($bin).
#  decode external sequence into Erlang object.
#
sub decode
{
	my $this = shift;
	my $out = $this->{log};
	
	my $data = shift;
	my $dataSz = length($data);
	my $offset = 0;

	$out and print $out "decode...\n";
	if( substr($data, 0, 1) ne $VERSION_MAGIC )
	{
		$out and print $out "no magic.\r\n";
		return;
	}
	$offset = 1;

	my @stack = ([]);
	my @pop = (0);

	my $SkipData = sub { $offset += $_[0]; };
	my $GetData = sub {
		my $sz = shift or return '';
		my $ret = substr($data, $offset, $sz);
		$offset += $sz;
		$ret;
	};
	my $GetCurData = sub { substr($data, $offset, $_[0]); };

	my $decode = {
		$NIL_EXT, sub {
			push(@{$stack[-1]}, []);
		},
		$SMALL_INTEGER_EXT, sub {
			push(@{$stack[-1]}, unpack("C",$GetData->(1)));
		},
		$INTEGER_EXT, sub {
			push(@{$stack[-1]}, unpack("N",$GetData->(4)));
		},
		$FLOAT_EXT, sub {
			my $s = $GetData->(31);
			$s =~ tr/\0//d;
			push(@{$stack[-1]}, $s);
		},
		$STRING_EXT, sub {
			push(@{$stack[-1]}, $GetData->(unpack("n",$GetData->(2))));
		},
		$ATOM_EXT, sub {
			push(@{$stack[-1]}, $this->_newAtom($GetData->(unpack("n",$GetData->(2)))));
		},
		$BINARY_EXT, sub {
			push(@{$stack[-1]}, $this->_newBinary($GetData->(unpack("N",$GetData->(4)))));
		},
		$LIST_EXT, sub {
			my $len = unpack("N",$GetData->(4));
			my $next = [];
			push(@{$stack[-1]}, $next);
			push(@stack, $next);
			push(@pop, $len);
			#next
		},
		$SMALL_TUPLE_EXT, sub {
			my $len = unpack("C",$GetData->(1));
			my $next = $this->_newTuple([]);
			push(@{$stack[-1]}, $next);
			push(@stack, $next);
			push(@pop, $len);
			#next;
		},
		$LARGE_TUPLE_EXT, sub {
			my $len = unpack("N",$GetData->(4));
			my $next = $this->_newTuple([]);
			push(@{$stack[-1]}, $next);
			push(@stack, $next);
			push(@pop, $len);
			#next;
		},
		$PID_EXT, sub {
			my $atom_mark = $GetData->(1);
			my $atom_len = unpack("n", $GetData->(2)) || 0;
			my $atom     = $GetData->($atom_len) || 0;
			my $pid      = unpack("N", $GetData->(4)) || 0;
			my $serial   = unpack("N", $GetData->(4)) || 0;
			my $creation = unpack("C", $GetData->(1)) || 0;
			my $obj = $this->_newPid([$atom, $pid, $serial, $creation]);
			push(@{$stack[-1]}, $obj);
		},
	};
	my %decode_skip_pop = ($LIST_EXT,1, $SMALL_TUPLE_EXT,1, $LARGE_TUPLE_EXT,1);

	while($offset < $dataSz)
	{
		my $opcode = $GetData->(1);
		my $code = $decode->{$opcode};
		if ($code) {
			$code->();
			next if exists $decode_skip_pop{$opcode};
		} else {
			#$REFERENCE_EXT     = 'e';
			#$NEW_REFERENCE_EXT = 'r';
			#$BIT_BINARY_EXT    = 'M';
			#$SMALL_BIG_EXT     = 'n';
			#$LARGE_BIG_EXT     = 'o';
			#$NEW_FUN_EXT       = 'p';
			#$EXPORT_EXT        = 'q';
			#$FUN_EXT           = 'u';
			#$NEW_CACHE         = 'N';
			#$CACHED_ATOM       = 'C';
			#$COMPRESSED        = 'P';
			my $chr = unpack("C",$opcode);
			$out and print $out "not ready $opcode ($chr).\r\n";
			last;
		}
		while( --$pop[-1]==0 )
		{
			pop @pop;
			pop @stack;
			if( !UNIVERSAL::isa($GetCurData->(), 'Erlang::Tuple') )
			{
				# List.
				$SkipData->(1) if $GetCurData->(1) eq $NIL_EXT;
				my $list = $stack[-1]->[-1];
				my $hash = {};
				foreach my $item (@$list)
				{
					if( !UNIVERSAL::isa($item, 'Erlang::Tuple') || @$item!=2 )
					{
						$hash = undef;
						last;
					}
					my $key = $this->to_s($item->[0]);
					if( !defined($key) )
					{
						$hash = undef;
						last;
					}
					$hash->{$key} = $item->[1];
				}
				if( $hash && @$list )
				{
					$stack[-1]->[-1] = $hash;
				}
			}
		}
	}
	$stack[0]->[0];
}

# -----------------------------------------------------------------------------
# $port->to_s($obj);
sub to_s
{
	my $this = shift;
	my $obj  = shift;
	if( defined($obj) && !ref($obj) )
	{
		$obj;
	}elsif( $obj && ref($obj) eq 'ARRAY' && @$obj==0 )
	{
		"";
	}elsif( ref($obj) && UNIVERSAL::isa($obj, 'Erlang::Atom') )
	{
		$$obj;
	}elsif( ref($obj) && UNIVERSAL::isa($obj, 'Erlang::Binary') )
	{
		$$obj;
	}else
	{
		undef;
	}
}

# -----------------------------------------------------------------------------
# $port->_newAtom($text) @ private.
#  create Erlang::Atom object.
#
sub _newAtom
{
	my $this = shift;
	my $atom = shift;
	bless \$atom, 'Erlang::Atom';
}

# -----------------------------------------------------------------------------
# $port->_newBinary($bytes) @ private.
#  create Erlang::Binary object.
#
sub _newBinary
{
	my $this = shift;
	my $binary = shift;
	bless \$binary, 'Erlang::Binary';
}

# -----------------------------------------------------------------------------
# $port->_newTuple($tuple) @ private.
#  create Erlang::Tuple object.
#
sub _newTuple
{
	my $this = shift;
	my $tuple = shift || [];
	bless $tuple, 'Erlang::Tuple';
}

# -----------------------------------------------------------------------------
# $port->_newPid(\@info) @ private.
#  create Erlang::Pid object.
#
sub _newPid
{
	my $this = shift;
	my $pid = shift;
	bless $pid, 'Erlang::Pid';
}

# -----------------------------------------------------------------------------
# $port->encode($obj).
#  encode Erlang obj into external sequence.
#
sub encode
{
	my $this = shift;
	my $obj  = shift;
	
	my $bin = $VERSION_MAGIC;
	$bin .= $this->_encode($obj);
	$bin;
}

# -----------------------------------------------------------------------------
# $port->_encode_list(@data) @ private.
#  encode multiple objects.
#
sub _encode_list
{
	my $this = shift;
	join('', map{ $this->_encode($_) } @_);
}

# -----------------------------------------------------------------------------
# $port->_encode($obj) @ private.
#  encode Erlang obj into external format.
#
sub _encode
{
	my $this = shift;
	my $obj  = shift;
	
	if( UNIVERSAL::isa($obj, 'Erlang::Atom') )
	{
		$ATOM_EXT . pack("n",length($$obj)) . $$obj;
	}elsif( UNIVERSAL::isa($obj, 'Erlang::Binary') )
	{
		$BINARY_EXT . pack("N",length($$obj)) . $$obj;
	}elsif( UNIVERSAL::isa($obj, 'Erlang::Pid') )
	{
		my ($atom, $pid, $serial, $creation) = @$obj;
		$PID_EXT . $ATOM_EXT . pack("n", length($atom)). $atom . pack("N", $pid) . pack("N", $serial) . pack("C", $creation);
	}elsif( UNIVERSAL::isa($obj, 'ARRAY') )
	{
		if( UNIVERSAL::isa($obj, 'Erlang::Tuple') )
		{
			my $n = @$obj;
			if( $n<256 )
			{
				$SMALL_TUPLE_EXT . pack("C",0+@$obj) . $this->_encode_list(@$obj);
			}else
			{
				$LARGE_TUPLE_EXT . pack("N",0+@$obj) . $this->_encode_list(@$obj);
			}
		}elsif( @$obj==0 )
		{
			$NIL_EXT;
		}else
		{
			$LIST_EXT . pack('N', 0+@$obj) . $this->_encode_list(@$obj, []);
		}
	}elsif( UNIVERSAL::isa($obj, 'HASH') )
	{
		# List of Tuples.
		my @conv;
		foreach my $key (sort keys %$obj)
		{
			my $atom = $this->_newAtom($key);
			push(@conv, $this->_newTuple([$atom, $obj->{$key}]));
		}
		$this->_encode(\@conv);
	}elsif( !ref($obj) )
	{
		if( !defined($obj) )
		{
			$this->_encode($this->_newAtom('undefined'));
		}elsif( $obj =~ /^-?\d+$/ && $obj eq unpack("N", pack("N",$obj)) )
		{
			if( $obj>=0 && $obj<=255 )
			{
				$SMALL_INTEGER_EXT . pack("C", $obj);
			}else
			{
				$INTEGER_EXT . pack("N", $obj);
			}
		}elsif( $obj =~ /^-?\d+(\.\d+)?(e[-+]?\d+)$/ )
		{
			$FLOAT_EXT . substr(sprintf("%.20e", $obj).("\0"x31), 0, 31);
		}else
		{
			$STRING_EXT . pack('n', length($obj)) . $obj;
		}
	}else
	{
		if( my $out = $this->{log} )
		{
			print $out "not ready [$obj].\r\n";
		}
		$this->_encode($this->_newAtom('encode_not_ready'));
	}
}

# -----------------------------------------------------------------------------
# End of Module.
# -----------------------------------------------------------------------------
__END__

=encoding utf8

=for stopwords
	YAMASHINA
	Hio
	ACKNOWLEDGEMENTS
	AnnoCPAN
	CPAN
	RT
	obj
	AnyObject

=head1 NAME

Erlang::Port4 - Erlang External Port (4-bytes packets)

=head1 VERSION

Version 0.04

=head1 SYNOPSIS

 use Erlang::Port4;
 
 my $port = Erlang::Port4->new(sub{ ... });
 $port->loop();

=head1 EXPORT

No functions are exported by this module.

=head1 METHODS

=head2 $pkg->new(\&CALLBACK);

=head2 $port->loop();

Wait request and Process it.

=head2 $pkg->encode($obj);

Encode Erlang obj into external sequence.

=head2 $pkg->decode($bytes);

Decode external sequence into Erlang object.

=head2 $pkg->to_s($obj);

Make string form of $obj.

=head1 EXAMPLES

See F<examples/> directory in this distribution.

F<examples/perlre.erl> has match(String, RegExp) 
and gsub(String, RegExp, Replacement).

F<examples/perleval.erl> has eval(String)
and set(VarName, AnyObject).

=head1 AUTHOR

YAMASHINA Hio, C<< <hio at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-erlang-port at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Erlang-Port4>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Erlang::Port4

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Erlang-Port4>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Erlang-Port4>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Erlang-Port4>

=item * Search CPAN

L<http://search.cpan.org/dist/Erlang-Port4>

=back

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2007 YAMASHINA Hio, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

