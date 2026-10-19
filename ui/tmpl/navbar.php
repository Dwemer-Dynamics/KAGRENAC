<?php // Presentation adapted from HerikaServer/ui/tmpl/navbar.php; see ../HERIKA-LICENSE. ?>
<div class="chim-navbar-wrapper">
    <nav class="navbar navbar-expand-lg chim-navbar" aria-label="Main">
        <div class="container-fluid mx-1">
            <div class="navbar-content-wrapper">
                <div class="navbar-center dropdown">
                    <button class="navbar-brand Title btn btn-link p-0 dropdown-toggle" id="brand-toggle" type="button" aria-expanded="false" aria-controls="brand-menu" title="KAGRENAC AI Mod Maker server: open menu">
                        <img src="<?= e($uiBase) ?>/images/kagrenac.png" alt="" width="53" height="50">
                        <span>KagrenacServer</span>
                    </button>
                    <ul class="dropdown-menu brand-menu" id="brand-menu">
                        <?php foreach ($sections as $key => $section): ?>
                        <li><a class="dropdown-item<?= $activeSection === $key ? ' active' : '' ?>" href="<?= e($uiBase . '/' . $section['href']) ?>" <?= $activeSection === $key ? 'aria-current="page"' : '' ?>><?= e($section['label']) ?></a></li>
                        <?php endforeach; ?>
                    </ul>
                </div>
            </div>
        </div>
    </nav>
</div>
