# Pin npm packages by running ./bin/importmap
# Stimulus and Turbo are pinned to ESM CDN so they resolve without vendored files.

pin "application"
pin "@hotwired/turbo-rails", to: "https://esm.sh/@hotwired/turbo@8.0.11", preload: true
pin "@hotwired/stimulus", to: "https://esm.sh/@hotwired/stimulus@3.2.2", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
