package Nginx::Simple;
use Exporter;

our $VERSION = '0.02';

@ISA = qw(Exporter);

use nginx;
use strict;

use Nginx::Simple::Cookie;

# data for output
my $output;

=head1 NAME

Nginx::Simple - Easy to use interface for "--with-http_perl_module"

=head1 SYNOPSIS

  nginx.conf:  
    perl_modules perl;
    perl_require Test.pm;

    server {
       listen       80;
       server_name  localhost;

       location / {
          perl Test::handler;
       }
    }

  Test.pm:
    package Test;
    use Nginx::Simple;

    sub handler { dispatch(shift) }

    sub main
    {
        my $self = shift;
        
        $self->header_set('Content-Type' => 'text/html');
        $self->print('rock on!');
	
        $self->log('I found a rabbit...');
        
        my $something = $self->param("here");
        $self->print("I found $something...");
    }

    # triggered on a server error
    sub error
    {
        my $self = shift;
        my $error = shift;

        $self->status(500);
        $self->print("oh, uh, there is an error! ($error)");
    }
    
=cut

sub import
{
    my ($class, $settings) = @_;
    our @EXPORT = qw(dispatch);
    
    __PACKAGE__->export_to_level(1, $class);
}

=head1 METHODS

=head3 $self->dispatch

sub header { dispatch(shift) }

Initial dispatcher, to be called by nginx.

=cut

sub dispatch
{
    my ($r, $sub, $error) = @_;

    my $init_caller = caller;
    $r->variable('init_caller', $init_caller  );
    $r->variable('init_sub',    $sub || 'main');
    $r->variable('error',       $error || ''  );

    if (not $error and $r->has_request_body(\&init_dispatcher))
    {
        return OK; 
    } 
    else
    {
        return &init_dispatcher($r);
    }

    return OK;
}

sub handler 
{
    my $r=shift;

    if ($r->has_request_body(\&handle_request_body))
    {
        return OK; 
    } 
    else
    {
        return &init_dispatcher($r);
    }

    return OK;
}

=head3 $self->server

Returns the nginx server object.

=cut

sub server           { shift->{server_object}              }

=head3 $self->uri

Returns the uri.

=cut

sub uri              { shift->server->uri                  }

=head3 $self->filename

Returns the path filename.

=cut

sub filename         { shift->server->filename             }

=head3 $self->request_method

Returns the request_method.

=cut

sub request_method   { shift->server->request_method       }

=head3 $self->remote_addr

Returns the remote_addr.

=cut

sub remote_addr      { shift->server->remote_addr          }

=head3 $self->header_in

Return value of header_in.

=cut

sub header_in        { shift->server->header_in(@_)        }

sub rflush           { shift->server->rflush               }
sub flush            { shift->rflush                       }


=head3 $self->print(...)

Output via http.

=cut

sub print 
{
    my $self = shift;

    $output .= join '', @_;
}

sub unescape         { shift->server->unescape(@_)         }

=head3 $self->header_set('header_type', 'value')

Set output header.

=cut

sub header_set 
{
    my ($self, $key, $value) = @_;

    $self->{headers}{$key} = $value;
}

=head3 $self->header('content-type')

Set content type.

=cut

sub header
{
    my ($self, $value) = @_;

    $self->header_set('Content-Type', $value);
}

=head3 $self->location('url')

Redirect to a url.

=cut

sub location         { shift->header_set('Location', shift) }

=head3 $self->status(...)

Set output status... (200, 404, etc...)

=cut

sub status 
{
    my ($self, $status) = @_;

    $self->{status} = $status;
}

# map $self->log to print STDERR
sub log              { shift; print STDERR @_;             }

=head3 $self->param(...)

Return a parameter passed via CGI--works like CGI::param.

=cut

sub param 
{
    my ($self, $lookup_key) = @_;
    
    my @values;
    my %seen_hash;
    my $request = $self->{args};

    if ($self->{request_parts})
    {
        for my $part (@{$self->{request_parts}})
        {
            if ($lookup_key)
            {
                push @values, $part->{data}
                    if $lookup_key eq $part->{name};
            }
            else
            {
                next if $seen_hash{$part->{name}}++;
                push @values, $part->{name};
            }
        }
    }
    else
    {
        my @args = split('&', $request);
        for my $arg (@args)
        {
            my ($key, $value) = split('=', $arg);
            
            if ($lookup_key)
            {
                push @values, $value if $lookup_key eq $key;
            }
            else
            {
                next if $seen_hash{$key}++;
                push @values, $key;
            }
        }
    }
    
    return unless @values;
    
    return (scalar @values == 1 ? $values[0] : @values);
}

=head3 $self->param_hash
    
Return a friendly hashref of CGI parameters.

=cut

sub param_hash
{
    my $self = shift;

    my %param_hash;
    
    for my $key ($self->param)
    {
        next if $param_hash{$key};
        
        my @params = $self->param($key);
        
        if (scalar @params == 1)
        {
            $param_hash{$key} = $params[0];
        }
        else
        {
            $param_hash{$key} = [ @params ],
        }
    }
    
    return \%param_hash;
}

sub handle_request_body
{
    my $r = shift;

    my $request_body = $r->request_body;

    my @r_body = split("\n", $request_body);

    my %params;

    if (scalar(@r_body) == 1)
    {
        $params{args} = $request_body;
    }
    else # process multi-line data
    {
        # decode multi-part data
        if ($r_body[0] =~ /^-/)
        {
            my @request_parts;

            # trim whitespace on header
            $r_body[0] =~ s/\s//g;

            # grab segments
            my @parts = split(/$r_body[0]\-*\s*/, $request_body);
            @parts = grep { $_ } @parts;

            for my $part (@parts)
            {
                my @lines = split("\n", $part);

                $_ .= "\n" for @lines;

                # grab header
                my @header;
                for my $line (@lines)
                {
                    my $t_line = shift @lines;

                    $t_line =~ s/[\r\n]//g;
                    push @header, $t_line if $t_line;

                    last unless $t_line;
                }

                $lines[-1] =~ s/[\r\n]//g;
                my $data = join('', @lines);

                my $name;
                if ($header[0] =~ /name="(.*?)"/)
                {
                    $name = $1;
                }

                push @request_parts, {
                    name   => $name,
                    header => \@header,
                    data   => $data,
                };
            }
            $params{request_parts} = \@request_parts;
        }
    }

    return &init_dispatcher($r, %params);
}

sub init_dispatcher {
    my ($r, %params) = @_;
    
    my $self = {
        server_object => $r,
        request       => $params{request} || $r->request_body,
        args          => $params{args}    || $r->args,
        request_parts => $params{request_parts},
        headers       => { 'Content-Type' => 'text/html' },
        status        => 200,
    };

    $output = q[];

    bless $self;
    
    my $init_caller = $r->variable('init_caller');
    my $init_sub    = $r->variable('init_sub');
    $r->variable('init_caller', undef);
    $r->variable('init_sub',    undef);

    my $sub_call = '';
    if ($init_sub =~ /::/)
    {
        $sub_call = $init_sub;
    }
    else
    {
        $init_caller =~ s/::([A-Za-z0-9_]*)//;
        $sub_call  = "$init_caller\::$init_sub";       
    }

    my ($class, $method) = $sub_call =~ /(.*?)::([A-Za-z0-9_]*)/;

    if (UNIVERSAL::can($class, $method))
    { 
        no strict 'refs';

        my $error = $self->server->variable('error');
        eval { $sub_call->($self, $error) };

        if ($@ and $@ ne "nginx-exit\n")
        {
            warn "$@\n";

            if ($method eq 'error')
            {
                # you've got an error in your error handler
                warn "Error in error handler... ($class\::error)\n";

                return $self->init_error($sub_call);
            }

            return &dispatch($self->server, "$class\::error", "$@");
        }
        else
        {
            $self->server->status($self->{status});
            
            my $content_type = delete $self->{headers}{'Content-Type'};

            $self->server->header_out($_, $self->{headers}{$_})
                for keys %{$self->{headers}};

            $self->server->send_http_header($content_type);

            $self->server->print($output);

            # ensure all data is transmitted
            $self->flush;

            return OK;
        }       
    }
    else
    {
        return $self->init_error($sub_call);
    }
}

sub init_error
{
    my ($self, $sub) = @_;
    
    warn(__PACKAGE__ . qq[: '$sub' does not exist...\n]) 
        unless $sub =~ /error$/;

    return HTTP_SERVER_ERROR;
}

=head3 $self->cookie

Cookie methods:

   $self->cookie->set(-name => 'foo', -value => 'bar');
   my %cookies = $self->cookie->read;

=cut

sub cookie { new Nginx::Simple::Cookie(shift) }

# override CORE::GLOBAL::exit & print
{
    no strict 'refs';
    *{"CORE::GLOBAL::exit"}  = sub { die "nginx-exit\n" };
    *{"CORE::GLOBAL::print"} = sub { };
}

=head1 Author

Michael J. Flickinger, C<< <mjflick@open-site.org> >>

=head1 Copyright & License

You may distribute under the terms of either the GNU General Public
License or the Artistic License.

=cut

1;
