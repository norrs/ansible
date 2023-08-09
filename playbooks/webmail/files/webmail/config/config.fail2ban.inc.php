<?php

  // Log successful/failed logins to <log_dir>/userlogins.log or to syslog
  // <log_dir> is default configured to RCUBE_INSTALL_PATH . 'logs/'
  $config['log_driver'] = 'file';
  $config['log_logins'] = true;