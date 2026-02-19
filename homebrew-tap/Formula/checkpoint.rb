class Checkpoint < Formula
  desc "Automated backup tool for developers — hourly snapshots of code, databases, and secrets"
  homepage "https://checkpoint.fluxcode.studio"
  url "https://github.com/fluxcodestudio/Checkpoint/archive/refs/tags/v2.5.2.tar.gz"
  # sha256 "UPDATE_WITH_ACTUAL_SHA256_AFTER_RELEASE"
  license "Polyform-Noncommercial-1.0.0"
  head "https://github.com/fluxcodestudio/Checkpoint.git", branch: "main"

  depends_on "bash"
  depends_on "git"

  def install
    # Install all scripts and libraries
    prefix.install Dir["*"]

    # Create symlinks for global commands
    bin.install_symlink prefix/"bin/backup-now.sh" => "backup-now"
    bin.install_symlink prefix/"bin/backup-status.sh" => "backup-status"
    bin.install_symlink prefix/"bin/backup-restore.sh" => "backup-restore"
    bin.install_symlink prefix/"bin/backup-cleanup.sh" => "backup-cleanup"
    bin.install_symlink prefix/"bin/backup-update.sh" => "backup-update"
    bin.install_symlink prefix/"bin/backup-pause.sh" => "backup-pause"
    bin.install_symlink prefix/"bin/backup-verify.sh" => "backup-verify"
    bin.install_symlink prefix/"bin/backup-cloud-config.sh" => "backup-cloud-config"
    bin.install_symlink prefix/"bin/backup-watch.sh" => "backup-watch"
    bin.install_symlink prefix/"bin/backup-all-projects.sh" => "backup-all"
  end

  def post_install
    # Create config directory
    (var/"checkpoint").mkpath
  end

  def caveats
    <<~EOS
      To start using Checkpoint, run:
        backup-now
      in any project directory.

      For the macOS menu bar dashboard:
        cd #{prefix}/helper && bash build.sh
        cp -r CheckpointHelper.app /Applications/

      Documentation: https://checkpoint.fluxcode.studio/docs.html
    EOS
  end

  test do
    assert_match "backup-now", shell_output("#{bin}/backup-now --help 2>&1", 1)
  end
end
