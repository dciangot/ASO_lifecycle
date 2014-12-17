----------------------------------------------------------------------
-- Create sequences

create sequence seq_dps_file;

----------------------------------------------------------------------
-- Create tables

create table t_dps_file
  (id			integer		not null,
   node			integer		not null,
   inblock		integer		not null,
   logical_name		varchar (1000)	not null,
   checksum		varchar (1000)	not null,
   filesize		integer		not null,
   time_create		float		not null,
   --
   constraint pk_dps_file
     primary key (id),
   --
   constraint uq_dps_file_logical_name
     unique (logical_name),
   --
   constraint fk_dps_file_node
     foreign key (node) references t_adm_node (id),
   --
   constraint fk_dps_file_inblock
     foreign key (inblock) references t_dps_block (id));


create table t_xfer_file
  (id			integer		not null,
   inblock		integer		not null,
   logical_name		varchar (1000)	not null,
   checksum		varchar (1000)	not null,
   filesize		integer		not null,
   --
   constraint pk_xfer_file
     primary key (id),
   --
   constraint uq_xfer_file_logical_name
     unique (logical_name),
   --
   constraint fk_xfer_file_id
     foreign key (id) references t_dps_file (id),
   --
   constraint fk_xfer_file_inblock
     foreign key (inblock) references t_dps_block (id));

-- /* Heirachical table to store a file path */
-- create table t_dps_dir (
--   parent     	       integer			,
--   id		       integer		not null,
--   pos		       integer		not null,
--   name		       varchar(1000)	not null,
--   time_create          float		not null,
--   --
--   constraint pk_dps_dir
--     primary key (id),
--   --
--   constraint uq_dps_dir_name
--     unique (parent, name),
--   --
--   constraint fk_dps_dir_parent
--     foreign key (parent) references t_dps_block_dir (id)
--     on delete cascade
-- );
-- 
-- create index ix_dps_dir_name 
--   on t_dps_dir (name);

----------------------------------------------------------------------
-- Create indices

create index ix_dps_file_node
  on t_dps_file (node);

create index ix_dps_file_inblock
  on t_dps_file (inblock);

--
create index ix_xfer_file_inblock
  on t_xfer_file (inblock);
