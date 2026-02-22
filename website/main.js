// ==========================================
// CHECKPOINT WEBSITE - MAIN JS
// Extracted from inline scripts for CSP compliance
// ==========================================

(function () {
    'use strict';

    // ==========================================
    // NAV TOGGLE (all pages)
    // ==========================================
    var navToggle = document.querySelector('.nav-toggle');
    if (navToggle) {
        navToggle.addEventListener('click', function () {
            this.nextElementSibling.classList.toggle('open');
        });
    }

    // ==========================================
    // EMAIL DEOBFUSCATION (legal pages)
    // ==========================================
    document.querySelectorAll('.eml').forEach(function (el) {
        var a = document.createElement('a');
        var e = el.dataset.u + '@' + el.dataset.d;
        a.href = 'mailto:' + e;
        a.textContent = e;
        el.replaceWith(a);
    });

    // ==========================================
    // CONTACT LINK (nav) - all pages
    // ==========================================
    var contactLink = document.querySelector('.nav-links a[href$="#contact"], .nav-links a[href="#"]');
    // More precise: find link by its text content
    document.querySelectorAll('.nav-links a').forEach(function (a) {
        if (a.textContent.trim() === 'Contact') {
            a.addEventListener('click', function (e) {
                if (window.openContactModal) {
                    e.preventDefault();
                    openContactModal();
                }
            });
        }
        if (a.textContent.trim() === 'Join Us') {
            a.addEventListener('click', function (e) {
                if (window.openNewsletterModal) {
                    e.preventDefault();
                    openNewsletterModal();
                }
            });
        }
    });

    // ==========================================
    // HERO DASHBOARD ANIMATION (index.html only)
    // ==========================================
    var heroCounter = document.querySelector('.dash-file-counter--hero');
    var heroBar = document.querySelector('.dash-progress-bar--hero');
    var heroStatus = document.querySelector('.dash-status-text--hero');
    if (heroCounter && heroBar && heroStatus) {
        var heroPhases = ['Initializing\u2026', 'Scanning for changes\u2026', 'Preparing files\u2026', 'Copying files\u2026', 'Verifying integrity\u2026', 'Writing manifest\u2026', 'Finalizing\u2026'];
        var heroTotal = 2847, heroPhase = 0, heroProg = 0;
        function heroTick() {
            heroProg += 0.15 + Math.random() * 0.35;
            if (heroProg >= 100) { heroProg = 0; heroPhase = (heroPhase + 1) % heroPhases.length; }
            heroCounter.textContent = Math.floor((heroProg / 100) * heroTotal).toLocaleString();
            heroBar.style.width = heroProg + '%';
            heroStatus.textContent = heroPhases[heroPhase];
            requestAnimationFrame(function () { setTimeout(heroTick, 30 + Math.random() * 20); });
        }
        heroTick();
    }

    // ==========================================
    // DASHBOARD SECTION ANIMATION (index.html only)
    // ==========================================
    var dashCounter = document.querySelector('.dash-file-counter:not(.dash-file-counter--hero)');
    var dashBar = document.querySelector('.dash-progress-bar:not(.dash-progress-bar--hero)');
    var dashStatus = document.querySelector('.dash-status-text:not(.dash-status-text--hero)');
    if (dashCounter && dashBar && dashStatus) {
        var dashPhases = ['Initializing\u2026', 'Scanning for changes\u2026', 'Preparing files\u2026', 'Copying files\u2026', 'Verifying integrity\u2026', 'Writing manifest\u2026', 'Finalizing\u2026'];
        var dashTotalFiles = 2847;
        var dashPhase = 0;
        var dashProgress = 0;
        function dashTick() {
            dashProgress += 0.15 + Math.random() * 0.35;
            if (dashProgress >= 100) {
                dashProgress = 0;
                dashPhase = (dashPhase + 1) % dashPhases.length;
            }
            var fc = Math.floor((dashProgress / 100) * dashTotalFiles);
            dashCounter.textContent = fc.toLocaleString();
            dashBar.style.width = dashProgress + '%';
            dashStatus.textContent = dashPhases[dashPhase];
            requestAnimationFrame(function () { setTimeout(dashTick, 30 + Math.random() * 20); });
        }
        dashTick();
    }

    // ==========================================
    // COPY BUTTON (index.html download section)
    // ==========================================
    var copyBtn = document.querySelector('.clone-block .copy-btn');
    if (copyBtn) {
        copyBtn.addEventListener('click', function () {
            var btn = this;
            navigator.clipboard.writeText('git clone https://github.com/fluxcodestudio/Checkpoint.git');
            btn.textContent = 'Copied!';
            setTimeout(function () { btn.textContent = 'Copy'; }, 2000);
        });
    }

    // ==========================================
    // MODAL FUNCTIONALITY (index.html only)
    // ==========================================

    // In-form error message (replaces alert())
    function showFormError(form, message) {
        var existing = form.querySelector('.form-error');
        if (existing) existing.remove();
        var err = document.createElement('div');
        err.className = 'form-error';
        err.textContent = message;
        form.querySelector('button[type="submit"]').before(err);
        setTimeout(function () { err.remove(); }, 8000);
    }

    // Contact Modal
    function openContactModal() {
        document.getElementById('contactModal').classList.add('active');
        document.body.style.overflow = 'hidden';
    }

    function closeContactModal() {
        document.getElementById('contactModal').classList.remove('active');
        document.body.style.overflow = '';
    }

    function submitContactForm(e) {
        e.preventDefault();
        var form = e.target;
        var formData = new FormData(form);
        // Honeypot check
        if (formData.get('company_url')) return;
        // Set email subject with prefix + user's subject
        var userSubject = formData.get('subject') || 'General Inquiry';
        formData.set('_subject', 'CONTACT: checkpoint.fluxcode.studio: ' + userSubject);
        var btn = form.querySelector('button[type="submit"]');
        btn.textContent = 'Sending...';
        btn.disabled = true;

        // If subscribe checkbox is checked, also add to Sendy
        if (formData.get('subscribe')) {
            var sendyData = new FormData();
            sendyData.append('email', formData.get('email'));
            sendyData.append('list', document.querySelector('#newsletterForm input[name="list"]').value);
            sendyData.append('subform', 'yes');
            sendyData.append('Source', 'Checkpoint Website - Contact Form');
            sendyData.append('Referrer', window.location.href);
            fetch(document.getElementById('newsletterForm').action, {
                method: 'POST',
                body: sendyData,
                mode: 'no-cors'
            }).catch(function () { });
        }

        // Remove subscribe checkbox from Formspree submission
        formData.delete('subscribe');

        // Submit to Formspree
        fetch(form.action, {
            method: 'POST',
            body: formData,
            headers: { 'Accept': 'application/json' }
        }).then(function (response) {
            if (response.ok) {
                var success = document.createElement('div');
                success.className = 'form-success';
                success.textContent = "Message sent! We'll get back to you soon.";
                form.replaceChildren(success);
                setTimeout(closeContactModal, 3000);
            } else {
                btn.textContent = 'Send Message';
                btn.disabled = false;
                showFormError(form, 'Something went wrong. Please try again or email ' + ['legal', 'fluxcode.studio'].join('@') + ' directly.');
            }
        }).catch(function () {
            btn.textContent = 'Send Message';
            btn.disabled = false;
            showFormError(form, 'Network error. Please try again or email ' + ['legal', 'fluxcode.studio'].join('@') + ' directly.');
        });
    }

    // Newsletter Modal
    function openNewsletterModal() {
        document.getElementById('newsletterModal').classList.add('active');
        document.body.style.overflow = 'hidden';
    }

    function closeNewsletterModal() {
        document.getElementById('newsletterModal').classList.remove('active');
        document.body.style.overflow = '';
        // Remember they've seen it
        localStorage.setItem('newsletterDismissed', 'true');
    }

    function submitNewsletterForm(e) {
        e.preventDefault();
        var form = e.target;
        var formData = new FormData(form);
        // Honeypot check -- bots fill hidden fields
        if (formData.get('last_name')) return;
        var btn = form.querySelector('button[type="submit"]');
        btn.textContent = 'Subscribing...';
        btn.disabled = true;

        // Submit to Sendy via AJAX
        fetch(form.action, {
            method: 'POST',
            body: formData,
            mode: 'no-cors' // Sendy may not have CORS headers
        }).then(function () {
            // Show success (we can't read response with no-cors)
            var success = document.createElement('div');
            success.className = 'form-success';
            success.textContent = "You're in! Check your email to confirm.";
            form.replaceChildren(success);
            setTimeout(closeNewsletterModal, 3000);
        }).catch(function () {
            // Fallback: submit normally
            form.submit();
        });
    }

    // Expose modal functions globally (needed for nav links on sub-pages)
    window.openContactModal = openContactModal;
    window.closeContactModal = closeContactModal;
    window.openNewsletterModal = openNewsletterModal;
    window.closeNewsletterModal = closeNewsletterModal;

    // ==========================================
    // MODAL EVENT LISTENERS (index.html only)
    // ==========================================

    // Contact modal backdrop click
    var contactModal = document.getElementById('contactModal');
    if (contactModal) {
        contactModal.addEventListener('click', function (event) {
            if (event.target === this) closeContactModal();
        });
    }

    // Contact modal close button
    var contactCloseBtn = contactModal ? contactModal.querySelector('.modal-close') : null;
    if (contactCloseBtn) {
        contactCloseBtn.addEventListener('click', function () {
            closeContactModal();
        });
    }

    // Contact form submit
    var contactForm = document.getElementById('contactForm');
    if (contactForm) {
        contactForm.addEventListener('submit', submitContactForm);
    }

    // Newsletter modal backdrop click
    var newsletterModal = document.getElementById('newsletterModal');
    if (newsletterModal) {
        newsletterModal.addEventListener('click', function (event) {
            if (event.target === this) closeNewsletterModal();
        });
    }

    // Newsletter modal close button
    var newsletterCloseBtn = newsletterModal ? newsletterModal.querySelector('.modal-close') : null;
    if (newsletterCloseBtn) {
        newsletterCloseBtn.addEventListener('click', function () {
            closeNewsletterModal();
        });
    }

    // Newsletter form submit
    var newsletterForm = document.getElementById('newsletterForm');
    if (newsletterForm) {
        newsletterForm.addEventListener('submit', submitNewsletterForm);
    }

    // Set referrer field on newsletter form
    var ref = document.querySelector('#newsletterForm input[name="Referrer"]');
    if (ref) ref.value = window.location.href;

    // Auto-show newsletter popup after 5 seconds
    if (document.getElementById('newsletterModal')) {
        // Don't show if already dismissed
        if (!localStorage.getItem('newsletterDismissed')) {
            setTimeout(function () {
                openNewsletterModal();
            }, 5000);
        }
    }

    // Close modals with Escape key
    document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape') {
            if (document.getElementById('contactModal')) closeContactModal();
            if (document.getElementById('newsletterModal')) closeNewsletterModal();
        }
    });

})();
