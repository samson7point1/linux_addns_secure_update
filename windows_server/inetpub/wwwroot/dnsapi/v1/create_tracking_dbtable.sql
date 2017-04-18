/*This script is designed to create a table in an Azure SQL DB*/
USE [ACMEAutomation]
GO

/****** Object:  Table [dbo].[dnsapi] ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [dbo].[dnsapi](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[date] [datetime] NULL,
	[user] [varchar](50) NULL,
	[ip] [varchar](50) NULL,
	[action] [varchar](max) NULL,
	[request] [varchar](max) NULL,
	[response] [varchar](max) NULL,
	[command] [varchar](max) NULL,
	[runtime] [numeric](30, 12) NULL
)

GO

SET ANSI_PADDING OFF
GO
