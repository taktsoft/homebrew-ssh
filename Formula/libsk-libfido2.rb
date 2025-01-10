class LibskLibfido2 < Formula
  desc "FIDO2 SecurityKeyProvider for native MacOS OpenSSH"
  homepage ""
  ## see https://opensource.apple.com/releases/ for new releases with apple patches
  url "https://github.com/apple-oss-distributions/OpenSSH/archive/refs/tags/OpenSSH-341.tar.gz"
  version "9.8p1"
  sha256 "3c63f3ec70c2c655c1a2805c5931a6bfe0d609e58cd60d99f443a7e4ebb9e035"
  license "SSH-OpenSSH"

  depends_on "pkg-config" => :build
  # depends_on "ldns"
  depends_on "libfido2"
  depends_on "openssl@3"

  bottle do
    root_url "https://github.com/taktsoft/homebrew-ssh/releases/download/v1.0"
    sha256 cellar: :any, arm64_sequoia: "91fc9dc7a84f2370fb27291fcad74935661215010457d1110bd2307f7a50f447"
  end

  def install
    puts "current path: #{Pathname.pwd}"
    puts "build path: #{buildpath}"
    cd ".." do
      system "mv", buildpath, "#{buildpath}.orig"
      system "mv", "#{buildpath}.orig/openssh", buildpath
    end

    ## patching
    patch_file_path = "#{buildpath}/standalone-libsk.patch"
    File.open(patch_file_path, "w") do |file|
      ## original patch: https://gist.github.com/thelastlin/c45b96cf460919e39ab5807b6d20ac2a#file-workaround-standalone-libsk-patch
      file.puts <<~PATCH
      diff --git a/sk-usbhid.c b/sk-usbhid.c
      index 7bb829aa..85c027a1 100644
      --- a/sk-usbhid.c
      +++ b/sk-usbhid.c
      @@ -75,10 +75,10 @@
       #define FIDO_CRED_PROT_UV_OPTIONAL_WITH_ID 0
       #endif
       
      +#include "misc.h"
       #ifndef SK_STANDALONE
       # include "log.h"
       # include "xmalloc.h"
      -# include "misc.h"
       /*
        * If building as part of OpenSSH, then rename exported functions.
        * This must be done before including sk-api.h.
      PATCH
    end
    system "patch", "-p1", "-i", patch_file_path, "-d", buildpath

    system "./configure", *std_configure_args, *%W[
      --sysconfdir=#{etc}/ssh
      --with-pam
      --with-audit=bsm
      --with-kerberos5=/usr
      --disable-libutil
      --disable-pututline
      --without-ldns
      --with-libedit
      --with-security-key-builtin
      --with-ssl-dir=#{Formula["openssl@3"].opt_prefix}
    ]
    
    system "make", "libssh.a", "CFLAGS=-O2 -fPIC"
    system "make", "openbsd-compat/libopenbsd-compat.a", "CFLAGS=-O2 -fPIC"
    system "make", "sk-usbhid.o", "CFLAGS=-O2 -DSK_STANDALONE -fPIC"

    system <<~BUILD_SCRIPT
      # set -v
      
      # cd openssh
      # ./configure --with-pam --with-audit=bsm --with-kerberos5=/usr \
      #  --disable-libutil \
      #  --disable-pututline \
      #  --with-default-path="/usr/bin:/bin:/usr/sbin:/sbin" \
      #  --with-cppflags="-I`xcodebuild -version -sdk macosx.internal Path`/usr/local/libressl/include" \
      #  --with-ldflags="-L`xcodebuild -version -sdk macosx.internal Path`/usr/local/libressl/lib" \
      #  --sysconfdir=/etc/ssh --without-ldns --with-libedit --with-pam --with-security-key-builtin \
      #  --with-ssl-dir=/opt/homebrew/opt/openssl@3/
      
      # make libssh.a CFLAGS="-O2 -fPIC"
      # make openbsd-compat/libopenbsd-compat.a CFLAGS="-O2 -fPIC"
      # make sk-usbhid.o CFLAGS="-O2 -DSK_STANDALONE -fPIC"
      
      export "$(cat Makefile | grep -m1 'CC=')" && \
      export "$(cat Makefile | grep -m1 'LDFLAGS=')" && \
      export "$(cat Makefile | grep -m1 'LIBFIDO2=')" && \
      echo $LIBFIDO2 | xargs ${CC} -shared openbsd-compat/libopenbsd-compat.a sk-usbhid.o libssh.a -O2 -fPIC -o libsk-libfido2.dylib -Wl,-dead_strip,-exported_symbol,_sk_\*
      BUILD_SCRIPT

    ENV.deparallelize

    lib.install "libsk-libfido2.dylib"
  
  end

  def caveats
    <<~EOS

      This library cannot be used with ssh-agent unless placed in /usr/local/lib (no symlink) or ssh-agent is started with '-P <dir>'. Please install manually:
      $ sudo cp #{lib}/libsk-libfido2.dylib /usr/local/lib/libsk-libfido2.dylib

      You may want to a similar configuration to your ~/.ssh/config:
      Host *
        SecurityKeyProvider /usr/local/lib/libsk-libfido2.dylib

      Example usage:
      $ ssh-keygen -t ecdsa-sk -w /usr/local/lib/libsk-libfido2.dylib -f ~/.ssh/id_ecdsa_sk -C "$USER-ecdsa-fido"
      $ ssh-add -S /usr/local/lib/libsk-libfido2.dylib ~/.ssh/id_ecdsa_sk
      $ ssh -o SecurityKeyProvider=/usr/local/lib/libsk-libfido2.dylib user@example.com -v -i ~/.ssh/id_ecdsa_sk

    EOS
  end

  test do
    system "false"
  end
end
