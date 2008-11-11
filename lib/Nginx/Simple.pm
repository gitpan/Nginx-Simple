package Nginx::Simple;
use Exporter;

our $VERSION = '0.01';

@ISA = qw(Exporter);

use nginx;
use strict;

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

    sub init
    {
	my $self = shift;
	
	$self->header('text/html');
	$self->print('rock on!');
	
	$self->log('I found a rabbit...');
	
	my $something = $self->param("here");
	$self->print("I found $something...");
	
	return OK;
    }
    
=cut

my ($caller_class, $caller_file);

sub import
{
    my ($class, $settings) = @_;
    our @EXPORT = qw(handler OK DENIED);

    ($caller_class, $caller_file) = caller;

    __PACKAGE__->export_to_level(1, $class);
}

sub handler {
    my $r=shift;

    if ($r->has_request_body(\&dispatch))
    {
	return OK; 
    } 
    else
    {
	return &dispatch($r);
    }

    return OK;
}

=head1 METHODS

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

sub rflush           { shift->server->rflush               }
sub flush            { shift->rflush                       }


=head3 $self->print(...)

Output to server.

=cut

sub print            { shift->server->print(@_)            }

sub unescape         { shift->server->unescape(@_)         }
sub sendfile         { shift->server->sendfile(@_)         }
sub send_http_header { shift->server->send_http_header(@_) }


=head3 $self->header(...)

Set output header.

=cut

sub header           { shift->send_http_header(@_)         }

=head3 $self->status(...)

Set output status... (200, 404, etc...)

=cut

sub status           { shift->server->status(@_)           }

# map $self->log to warn
sub log              { shift; warn(@_);                    }

=head3 $self->param(...)

Return a parameter passed via CGI--works like CGI::param.

=cut

sub param 
{
    my ($self, $lookup_key) = @_;

    my @values;
    my $request = $self->{request} || $self->{args};

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
	    push @values, $key;
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

sub dispatch {
    my $r = shift;

    my $self = {
	server_object => $r,
	request       => $r->request_body,
	args          => $r->args,
    };
    bless $self;

    if ($caller_class->can('init'))
    { 
	no strict 'refs';	
	my $caller_sub = "$caller_class\::init";
	return &$caller_sub($self);
    }
    else
    {
	return $self->init_error;
    }
}

sub init_error
{
    my $self = shift;
    
    $self->header('text/html');

    warn(__PACKAGE__ . qq[: sub init not found in $caller_file...\n]);
    $self->print("Main dispatcher not configured.");
    
    return OK;
}

=head1 Author

Michael J. Flickinger, C<< <mjflick@open-site.org> >>

=head1 Copyright & License

You may distribute under the terms of either the GNU General Public
License or the Artistic License.

=cut


1;

