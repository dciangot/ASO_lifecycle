update t_xfer_request set time_expire = 0 where state = 1 and time_expire > 0;
