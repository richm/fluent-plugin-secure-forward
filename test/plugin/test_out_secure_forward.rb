require 'helper'

class SecureForwardOutputTest < Test::Unit::TestCase
  CONFIG = %[
]

  def setup
    Fluent::Test.setup
  end

  def create_driver(conf=CONFIG,tag='test')
    Fluent::Test::OutputTestDriver.new(Fluent::SecureForwardOutput, tag).configure(conf)
  end

  def get_ca_cert
    ca_dir = File.join(Dir.pwd, "test", "tmp", "cadir")
    unless File.exist?(File.join(ca_dir, 'ca_cert.pem'))
      FileUtils.mkdir_p(ca_dir)
      opt = {
        private_key_length: 2048,
        cert_country:  'US',
        cert_state:    'CA',
        cert_locality: 'Mountain View',
        cert_common_name: 'SecureForward CA',
      }
      cert, key = Fluent::SecureForward::CertUtil.generate_ca_pair(opt)
      key_data = key.export(OpenSSL::Cipher::Cipher.new('aes256'), passphrase)
      File.open(File.join(ca_dir, 'ca_key.pem'), 'w') do |file|
        file.write key_data
      end
      File.open(File.join(ca_dir, 'ca_cert.pem'), 'w') do |file|
        file.write cert.to_pem
      end
    end
    File.join(ca_dir, 'ca_cert.pem')
  end

  def test_configure_secondary
    p1 = nil
    assert_nothing_raised { p1 = create_driver(<<CONFIG).instance }
  type secure_forward
  secure no
  shared_key secret_string
  self_hostname client.fqdn.local
  <server>
    host server.fqdn.local  # or IP
    # port 24284
  </server>
  <secondary>
    type forward
    <server>
      host localhost
    </server>
  </secondary>
CONFIG
  end

  def test_configure_standby_server
    p1 = nil
    assert_nothing_raised { p1 = create_driver(<<CONFIG).instance }
  type secure_forward
  secure no
  shared_key secret_string
  self_hostname client.fqdn.local
  keepalive 1m
  <server>
    host server1.fqdn.local
  </server>
  <server>
    host server2.fqdn.local
    hostlabel server2
  </server>
  <server>
    host server1.fqdn.local
    hostlabel server1
    port 24285
    shared_key secret_string_more
    standby
  </server>
CONFIG
    assert_equal 3, p1.servers.size
    assert_equal 3, p1.nodes.size

    assert_equal 'server1.fqdn.local', p1.nodes[0].host
    assert_equal 'server1.fqdn.local', p1.nodes[0].hostlabel
    assert_equal 24284, p1.nodes[0].port
    assert_equal false, p1.nodes[0].standby
    assert_equal 'secret_string', p1.nodes[0].shared_key
    assert_equal 60, p1.nodes[0].keepalive

    assert_equal 'server2.fqdn.local', p1.nodes[1].host
    assert_equal 'server2', p1.nodes[1].hostlabel
    assert_equal 24284, p1.nodes[1].port
    assert_equal false, p1.nodes[1].standby
    assert_equal 'secret_string', p1.nodes[1].shared_key
    assert_equal 60, p1.nodes[1].keepalive

    assert_equal 'server1.fqdn.local', p1.nodes[2].host
    assert_equal 'server1', p1.nodes[2].hostlabel
    assert_equal 24285, p1.nodes[2].port
    assert_equal true, p1.nodes[2].standby
    assert_equal 'secret_string_more', p1.nodes[2].shared_key
    assert_equal 60, p1.nodes[2].keepalive
  end

  def test_configure_standby_server2
    p1 = nil
    assert_nothing_raised { p1 = create_driver(<<CONFIG).instance }
  type secure_forward
  secure no
  shared_key secret_string
  self_hostname client.fqdn.local
  num_threads 3
  <server>
    host server1.fqdn.local
  </server>
  <server>
    host server2.fqdn.local
  </server>
  <server>
    host server3.fqdn.local
    standby
  </server>
CONFIG
    assert_equal 3, p1.num_threads
    assert_equal 1, p1.log.logs.select{|line| line =~ /\[warn\]: Too many num_threads for secure-forward:/}.size
  end

  def test_configure_with_ca_cert
    p = nil
    assert_nothing_raised { p = create_driver(<<CONFIG).instance }
  type secure_forward
  secure yes
  ca_cert_path #{get_ca_cert}
  shared_key secret_string
  self_hostname client.fqdn.local
  num_threads 3
  <server>
    host server1.fqdn.local
  </server>
  <server>
    host server2.fqdn.local
  </server>
  <server>
    host server3.fqdn.local
    standby
  </server>
CONFIG
  end

  def test_configure_using_hostname
    my_system_hostname = Socket.gethostname

    d = create_driver(%[
      secure no
      shared_key secret_string
      self_hostname ${hostname}
      <server>
        host server.fqdn.local  # or IP
        # port 24284
      </server>
    ])
    assert_equal my_system_hostname, d.instance.self_hostname

    d = create_driver(%[
      secure no
      shared_key secret_string
      self_hostname __HOSTNAME__
      <server>
        host server.fqdn.local  # or IP
        # port 24284
      </server>
    ])
    assert_equal my_system_hostname, d.instance.self_hostname

    d = create_driver(%[
      secure no
      shared_key secret_string
      self_hostname test.${hostname}
      <server>
        host server.fqdn.local  # or IP
        # port 24284
      </server>
    ])
    assert_equal "test.#{my_system_hostname}", d.instance.self_hostname

    d = create_driver(%[
      secure no
      shared_key secret_string
      hostname dummy.local
      self_hostname test.${hostname}
      <server>
        host server.fqdn.local  # or IP
        # port 24284
      </server>
    ])
    assert_equal "test.dummy.local", d.instance.self_hostname
  end

  def test_configure_with_sni_hostname
    p = nil
    assert_nothing_raised { p = create_driver(<<CONFIG).instance }
  type secure_forward
  secure yes
  ca_cert_path #{get_ca_cert}
  shared_key secret_string
  self_hostname client.fqdn.local
  num_threads 3
  <server>
    host server1.fqdn.local
    sni_hostname real.server.fqdn.local
  </server>
CONFIG
    assert_equal 'real.server.fqdn.local', p.nodes[0].sni_hostname
  end

end
