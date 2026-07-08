-- ─────────────────────────────────────────────────────────────
--  v-core database schema  (database: projet_r)
--  Engine: MariaDB / InnoDB, utf8mb4
--  Author: vyrriox
-- ─────────────────────────────────────────────────────────────
SET NAMES utf8mb4;

-- Accounts — one row per FiveM license.
CREATE TABLE IF NOT EXISTS `users` (
  `license`    VARCHAR(60) NOT NULL,
  `name`       VARCHAR(64) DEFAULT NULL,
  `permission` VARCHAR(20) NOT NULL DEFAULT 'user',   -- user / mod / admin / superadmin
  `language`   VARCHAR(5)  NOT NULL DEFAULT 'fr',     -- fr / en
  `created_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_seen`  TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Characters — supports multiple characters per account.
CREATE TABLE IF NOT EXISTS `characters` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `citizenid`  VARCHAR(16)  NOT NULL,
  `license`    VARCHAR(60)  NOT NULL,
  `slot`       TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `firstname`  VARCHAR(50)  NOT NULL DEFAULT 'John',
  `lastname`   VARCHAR(50)  NOT NULL DEFAULT 'Doe',
  `dob`        VARCHAR(20)  NOT NULL DEFAULT '2000-01-01',
  `sex`        TINYINT      NOT NULL DEFAULT 0,          -- 0 male, 1 female
  `cash`       BIGINT       NOT NULL DEFAULT 500,
  `bank`       BIGINT       NOT NULL DEFAULT 5000,
  `job`        VARCHAR(50)  NOT NULL DEFAULT 'unemployed',
  `job_grade`  INT          NOT NULL DEFAULT 0,
  `gang`       VARCHAR(50)  NOT NULL DEFAULT 'none',
  `gang_grade` INT          NOT NULL DEFAULT 0,
  `position`   JSON         DEFAULT NULL,
  `metadata`   JSON         DEFAULT NULL,
  `inventory`  JSON         DEFAULT NULL,
  `appearance` JSON         DEFAULT NULL,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `citizenid` (`citizenid`),
  KEY `license` (`license`),
  CONSTRAINT `fk_char_user` FOREIGN KEY (`license`) REFERENCES `users` (`license`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Item definitions — managed from the admin panel.
CREATE TABLE IF NOT EXISTS `items` (
  `name`      VARCHAR(50)  NOT NULL,
  `label`     VARCHAR(80)  NOT NULL,
  `weight`    INT          NOT NULL DEFAULT 0,           -- grams
  `stackable` TINYINT(1)   NOT NULL DEFAULT 1,
  `usable`    TINYINT(1)   NOT NULL DEFAULT 0,
  `category`  VARCHAR(40)  NOT NULL DEFAULT 'misc',
  `image`     VARCHAR(120) DEFAULT NULL,
  `price`     INT          NOT NULL DEFAULT 0,           -- default shop price
  `metadata`  JSON         DEFAULT NULL,
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Owned vehicles.
CREATE TABLE IF NOT EXISTS `character_vehicles` (
  `id`        INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(16)  NOT NULL,
  `plate`     VARCHAR(12)  NOT NULL,
  `model`     VARCHAR(50)  NOT NULL,
  `props`     JSON         DEFAULT NULL,
  `garage`    VARCHAR(50)  NOT NULL DEFAULT 'legion',
  `state`     TINYINT      NOT NULL DEFAULT 1,           -- 0 out, 1 garaged, 2 impound
  `fuel`      INT          NOT NULL DEFAULT 100,
  `engine`    FLOAT        NOT NULL DEFAULT 1000,
  `body`      FLOAT        NOT NULL DEFAULT 1000,
  `created_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `plate` (`plate`),
  KEY `citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Jobs + grades — managed from the admin panel.
CREATE TABLE IF NOT EXISTS `jobs` (
  `name`  VARCHAR(50) NOT NULL,
  `label` VARCHAR(80) NOT NULL,
  `type`  VARCHAR(20) NOT NULL DEFAULT 'civ',            -- civ / leo / ems / gang / mafia
  `grades` JSON NOT NULL,                                -- [{grade,name,salary,isboss}]
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Gangs / mafias + grades — managed from the admin panel.
CREATE TABLE IF NOT EXISTS `gangs` (
  `name`  VARCHAR(50) NOT NULL,
  `label` VARCHAR(80) NOT NULL,
  `type`  VARCHAR(20) NOT NULL DEFAULT 'gang',           -- gang / mafia
  `grades` JSON NOT NULL,
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Shops — managed from the admin panel.
CREATE TABLE IF NOT EXISTS `shops` (
  `id`    VARCHAR(50) NOT NULL,
  `label` VARCHAR(80) NOT NULL,
  `type`  VARCHAR(30) NOT NULL DEFAULT 'general',
  `coords` JSON DEFAULT NULL,
  `items` JSON NOT NULL,                                 -- [{item, price}]
  `job`   VARCHAR(50) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Live server config the admin panel can tweak without a restart.
CREATE TABLE IF NOT EXISTS `server_config` (
  `key`   VARCHAR(64) NOT NULL,
  `value` JSON NOT NULL,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Structured logs (admin actions, economy, anti-cheat, ...).
CREATE TABLE IF NOT EXISTS `logs` (
  `id`        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `category`  VARCHAR(40) NOT NULL,
  `citizenid` VARCHAR(16) DEFAULT NULL,
  `message`   VARCHAR(255) NOT NULL,
  `data`      JSON DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `category` (`category`),
  KEY `citizenid` (`citizenid`),
  KEY `created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─── Seed data ───────────────────────────────────────────────
INSERT IGNORE INTO `items` (`name`,`label`,`weight`,`stackable`,`usable`,`category`,`price`) VALUES
  ('water','Water Bottle',500,1,1,'food',5),
  ('bread','Bread',300,1,1,'food',5),
  ('phone','Phone',400,0,1,'gadget',250),
  ('lockpick','Lockpick',100,1,1,'tool',75),
  ('bandage','Bandage',100,1,1,'medical',15),
  ('cash','Marked Cash',0,1,0,'money',0);

INSERT IGNORE INTO `jobs` (`name`,`label`,`type`,`grades`) VALUES
  ('unemployed','Unemployed','civ', JSON_ARRAY(JSON_OBJECT('grade',0,'name','Civilian','salary',10,'isboss',false))),
  ('police','Police','leo', JSON_ARRAY(
     JSON_OBJECT('grade',0,'name','Cadet','salary',50,'isboss',false),
     JSON_OBJECT('grade',1,'name','Officer','salary',75,'isboss',false),
     JSON_OBJECT('grade',4,'name','Chief','salary',150,'isboss',true))),
  ('ambulance','EMS','ems', JSON_ARRAY(
     JSON_OBJECT('grade',0,'name','Trainee','salary',50,'isboss',false),
     JSON_OBJECT('grade',3,'name','Doctor','salary',120,'isboss',true)));

INSERT IGNORE INTO `gangs` (`name`,`label`,`type`,`grades`) VALUES
  ('none','No Gang','gang', JSON_ARRAY(JSON_OBJECT('grade',0,'name','None','isboss',false))),
  ('ballas','Ballas','gang', JSON_ARRAY(
     JSON_OBJECT('grade',0,'name','Recruit','isboss',false),
     JSON_OBJECT('grade',2,'name','Boss','isboss',true)));

INSERT IGNORE INTO `shops` (`id`,`label`,`type`,`items`) VALUES
  ('convenience','24/7 Store','general', JSON_ARRAY(
     JSON_OBJECT('item','water','price',5),
     JSON_OBJECT('item','bread','price',5),
     JSON_OBJECT('item','phone','price',250)));
