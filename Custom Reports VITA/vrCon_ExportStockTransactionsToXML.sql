USE [vbdcm]
GO
/****** Object:  StoredProcedure [dbo].[vrCon_ExportStockTransactionsToXML]    Script Date: 17.08.2017 11:53:38 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*

	Name:			vrCon_ExportStockTransactionsToXML

	Description:	Export stockadjustments to XML
					No fancy stuff - just write line by line
					
	Requirements:	

	Uses:			spWriteStringToFile

	ToDo:			

	Date:			2017-08-16

	By:				D. Molde, Visma Retail

	Modifications:  

	Usage:
					Input parameters are range of transactioncounters
					Example:	EXEC vrCon_ExportStockTransactionsToXML 227080093,227279974

					To get correct encoding (UTF-8) it is necessary to change encoding
					Easy way - use PowerShell:

					Get-Content inputfile.xml | Set-Content -Encoding utf8 outputfile.xml
				
*/


ALTER PROCEDURE [dbo].[vrCon_ExportStockTransactionsToXML] 	(@FromTransactionCounter BIGINT, @ToTransactionCounter BIGINT)
AS
BEGIN

	set nocount on

	Declare @FileRecord varchar(4000)
	Declare @Filename varchar(255)
	Declare @PathAndFilename varchar(255)
	Declare @Date varchar(200)
	Declare @CrLf char(2)
	Declare @Tab char(1)
	Declare @TotalNumberOfItemLines bigint
	Declare @String varchar(4000)
	Declare @Num int
	Declare @NumberOfRecords int
	Declare @FileBuffer varchar(max)
	Declare @BufferFill int
	Declare @MaxFill int

	Declare @Stock_StoreID varchar(200)
	Declare @Stock_ArticleID varchar(200)
	Declare @Stock_GtinNo varchar(200)
	Declare @Stock_InStockQty varchar(200)
	Declare @Stock_BStockQty varchar(200)
	Declare @Stock_OnDisplayQty varchar(200)
	Declare @Stock_HomeLoanQty varchar(200)
	Declare @Stock_OnServiceQty varchar(200)
	Declare @Stock_StockInTransitQty varchar(200)
	Declare @Stock_NotDeliveredQty varchar(200)
	Declare @Stock_ReservedStockQty varchar(200)
	Declare @Stock_ReservedStockInOrderQty varchar(200)
	Declare @Stock_StockInOrderQty varchar(200)
	Declare @Stock_LastUpdatedStockCount varchar(200)
	Declare @Stock_LastUpdatedSoldDate varchar(200)
	Declare @Stock_LastPurchased varchar(200)
	Declare @Stock_LastReceived varchar(200)
	Declare @Stock_ModifiedDate varchar(200)
	Declare @Adj_TransactionCounter varchar(200)
	Declare @Adj_AdjustmentDate varchar(200)
	Declare @Adj_StockAdjReasonNo varchar(200)
	Declare @Adj_StockAdjType varchar(200)
	Declare @Adj_AdjustmentQty varchar(200)
	Declare @Adj_NetPrice varchar(200)
	Declare @Adj_DerivedNetCostAmount varchar(200)
	Declare @Adj_NetSalesPrice varchar(200)
	Declare @Adj_SalesPrice varchar(200)
	Declare @Adj_LinkQty varchar(200)
	Declare @Adj_LinkArticleID varchar(200)
	Declare @Adj_LinkGtinNo varchar(200)
	Declare @Adj_StockCountNo varchar(200)
	Declare @Adj_AdjustmentRefNo varchar(200)
	Declare @Stock_ExportTimestamp varchar(200)
	Declare @Adj_IsMaster varchar(200)
	Declare @Adj_UserID varchar(200)
	DECLARE @Adj_LotNumber varchar(200)
	DECLARE @Adj_SupplierID varchar(200)
	DECLARE @Adj_SupplierType varchar(200)

	Declare @ConversationId varchar(1000)
	Declare @StrMsg varchar(2000)


	--	Initialize variables
	set @FileBuffer = ''
	set @BufferFill = 0
	set @NumberOfRecords = 0
	set @MaxFill = 100
	set @CrLf = CHAR(13) + CHAR(10) 
	set @Date =	CONVERT(varchar(200),GETDATE(),126)
	SET @ConversationId = CAST(NEWID() AS varchar(1000))

	set @PathAndFilename = 'C:\Temp\CIM.External.Export.StockTransactions.v2_' + LEFT(@Date,10) + '_' + @ConversationId + '.xml'

	--	Init
	SET @FileBuffer = @FileBuffer + '<?xml version="1.0" encoding="utf-8"?>'
	SET @FileBuffer = @FileBuffer + @CrLf
	SET @FileBuffer = @FileBuffer + '<RS xmlns:h="http://schemas.vismaretail.com/common/header/v2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns="http://schemas.vismaretail.com/external/StockTransactions/v2">'
	SET @FileBuffer = @FileBuffer + @CrLf
	SET @FileBuffer = @FileBuffer + '	<Header>'
	SET @FileBuffer = @FileBuffer + @CrLf
	SET @FileBuffer = @FileBuffer + '		<Source xmlns="">'
	SET @FileBuffer = @FileBuffer + @CrLf
	SET @FileBuffer = @FileBuffer + '			<Name>Logistics</Name>'
	SET @FileBuffer = @FileBuffer + @CrLf
	SET @FileBuffer = @FileBuffer + '		</Source>'
	SET @FileBuffer = @FileBuffer + @CrLf
	SET @FileBuffer = @FileBuffer + '		<Message xmlns="">'
	SET @FileBuffer = @FileBuffer + @CrLf
	SET @FileBuffer = @FileBuffer + '			<ConversationId>' + @ConversationId + '</ConversationId>'
	SET @FileBuffer = @FileBuffer + @CrLf
	SET @FileBuffer = @FileBuffer + '			<CreatedDate>'+@Date+'</CreatedDate>'
	SET @FileBuffer = @FileBuffer + @CrLf
	SET @FileBuffer = @FileBuffer + '			<SentDate>'+@Date+'</SentDate>'
	SET @FileBuffer = @FileBuffer + @CrLf
	SET @FileBuffer = @FileBuffer + '			<ContentType>CIM.External.Export.StockTransactions.v2</ContentType>'
	SET @FileBuffer = @FileBuffer + @CrLf
	SET @FileBuffer = @FileBuffer + '		</Message>'
	SET @FileBuffer = @FileBuffer + @CrLf
	SET @FileBuffer = @FileBuffer + '	</Header>'
	SET @FileBuffer = @FileBuffer + @CrLf
	SET @FileBuffer = @FileBuffer + '	<StockTransactions>'
	SET @FileBuffer = @FileBuffer + @CrLf

	SET @StrMsg = 'Writing header'
	RAISERROR(@StrMsg, 0, 42) WITH NOWAIT;	

	Exec dbo.spWriteStringToFile @FileBuffer, @PathAndFilename, 0
	Set @FileBuffer = ''

	Declare StockCursor CURSOR FAST_FORWARD FOR
		SELECT 
			StoreId_TestRS = CAST(sm.StoreId_TestRS AS varchar),
			ArticleID = aa.ArticleID, 
			GTIN = CAST(aa.PrimaryEAN AS varchar),
			InStockQty = ISNULL(CAST(sai.InStockQty AS varchar),'0'), 
			BStockQty = ISNULL(CAST(sai.BStockQty AS varchar), '0'), 
			OnDisplayQty = ISNULL(CAST(sai.OnDisplayQty AS varchar),'0'), 
			HomeLoanQty = ISNULL(CAST(sai.HomeLoanQty AS varchar), '0'), 
			OnServiceQty = ISNULL(CAST(sai.OnServiceQty AS varchar), '0'), 
			StockInTransitQty = ISNULL(CAST(sai.StockInTransitQty AS varchar),'0'), 
			NotDeliveredQty = ISNULL(CAST(sai.NotDeliveredQty AS varchar), '0'), 
			ReservedStockQty = ISNULL(CAST(sai.ReservedStockQty AS varchar), '0'), 
			ReservedStockInOrderQty = '0', 
			StockInOrderQty = ISNULL(CAST(sai.StockInOrderQty AS varchar),  '0'), 
			LastUpdatedStockCount = ISNULL(CONVERT(varchar(100),sai.LastUpdatedStockCount,126),''),
			LastUpdatedSoldDate = ISNULL(CONVERT(varchar(100),sai.LastUpdatedSoldDate,126),''), 
			LastPurchased = ISNULL(CONVERT(varchar(100),sai.LastPurchased,126),''),
			LastReceived = ISNULL(CONVERT(varchar(100),sai.LastReceived,126),''), 
			Recordcreated = ISNULL(CONVERT(varchar(100),sai.Recordcreated,126),''),
			TransactionCounter = CAST(sa.TransactionCounter AS varchar),
			AdjustmentDate = ISNULL(CONVERT(varchar(100),sa.AdjustmentDate,126),''),
			StockAdjReasonNo = ISNULL(CAST(sa.StockAdjReasonNo AS varchar), '0'), 
			StockAdjType = ISNULL(CAST(sa.StockAdjType AS varchar), '0'), 
			AdjustmentQty = ISNULL(CAST(sa.AdjustmentQty AS varchar), '0'), 
			NetPrice = ISNULL(CAST(sa.NetPrice AS varchar), '0'), 
			DerivedNetCostAmount = ISNULL(CAST(sa.DerivedNetCostAmount AS varchar), '0'), 
			NetSalesPrice = ISNULL(CAST(sa.NetSalesPrice AS varchar), '0'), 
			SalesPrice = ISNULL(CAST(sa.SalesPrice AS varchar), '0'), 
			LinkQty = '0',
			LinkArticleID = '',
			LinkGtinNo = '',
			StockCountNo = CASE WHEN StockAdjType IN (51,52) THEN ISNULL(sa.AdjustmentRefNo, '')  ELSE '' END,
			AdjustmentRefNo = ISNULL(sa.AdjustmentRefNo, ''), 
			Stock_ExportTimestamp = CONVERT(varchar(100),GETDATE(),126),
			IsMaster = 'false',
			UserID = ISNULL(CAST(sa.UserNo AS varchar), ''),
			LotNumber = 0,
			SupplierID = so.SupplierID,
			SupplierType = so.SupplierType
		FROM
			vbdcm.dbo.VRPS_StoreMapping sm JOIN
			vbdcm.dbo.Stores s ON sm.StoreNo_LogWeb = s.StoreNo JOIN
			vbdcm.dbo.StockAdjustments sa ON s.StoreNo = sa.StoreNo JOIN
			vbdcm.dbo.AllArticles aa ON sa.ArticleNo = aa.ArticleNo LEFT JOIN
			vbdcm.dbo.StoreArticleInfos sai ON (sai.StoreNo = s.StoreNo AND sai.ArticleNo = aa.ArticleNo) LEFT JOIN
			vbdcm.dbo.SupplierOrgs so ON aa.SupplierNo = so.SupplierNo
		WHERE
		--	sa.AdjustmentDate > '2017-08-06'
			sa.TransactionCounter BETWEEN @FromTransactionCounter AND @ToTransactionCounter
			AND sa.StockAdjType <> 1
		ORDER BY
			sa.AdjustmentDate DESC


	Open StockCursor

	FETCH NEXT FROM StockCursor
	INTO	
		@Stock_StoreID,
		@Stock_ArticleID,
		@Stock_GtinNo,
		@Stock_InStockQty,
		@Stock_BStockQty,
		@Stock_OnDisplayQty,
		@Stock_HomeLoanQty,
		@Stock_OnServiceQty,
		@Stock_StockInTransitQty,
		@Stock_NotDeliveredQty,
		@Stock_ReservedStockQty,
		@Stock_ReservedStockInOrderQty,
		@Stock_StockInOrderQty,
		@Stock_LastUpdatedStockCount,
		@Stock_LastUpdatedSoldDate,
		@Stock_LastPurchased,
		@Stock_LastReceived,
		@Stock_ModifiedDate,
		@Adj_TransactionCounter,
		@Adj_AdjustmentDate,
		@Adj_StockAdjReasonNo,
		@Adj_StockAdjType,
		@Adj_AdjustmentQty,
		@Adj_NetPrice,
		@Adj_DerivedNetCostAmount,
		@Adj_NetSalesPrice,
		@Adj_SalesPrice,
		@Adj_LinkQty,
		@Adj_LinkArticleID,
		@Adj_LinkGtinNo,
		@Adj_StockCountNo,
		@Adj_AdjustmentRefNo,
		@Stock_ExportTimestamp,
		@Adj_IsMaster,
		@Adj_UserId,
		@Adj_LotNumber,
		@Adj_SupplierID,
		@Adj_SupplierType

	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @FileBuffer = @FileBuffer + '		<StockTransaction>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Stock_StoreID>' + @Stock_StoreID + '</Stock_StoreID>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Stock_ArticleID>' + @Stock_ArticleID + '</Stock_ArticleID>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Stock_GtinNo>' + @Stock_GtinNo + '</Stock_GtinNo>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Stock_InStockQty>' + @Stock_InStockQty + '</Stock_InStockQty>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Stock_BStockQty>' + @Stock_BStockQty + '</Stock_BStockQty>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Stock_OnDisplayQty>' + @Stock_OnDisplayQty + '</Stock_OnDisplayQty>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Stock_HomeLoanQty>' + @Stock_HomeLoanQty + '</Stock_HomeLoanQty>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Stock_OnServiceQty>' + @Stock_OnServiceQty + '</Stock_OnServiceQty>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Stock_StockInTransitQty>' + @Stock_StockInTransitQty + '</Stock_StockInTransitQty>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Stock_NotDeliveredQty>' + @Stock_NotDeliveredQty + '</Stock_NotDeliveredQty>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Stock_ReservedStockQty>' + @Stock_ReservedStockQty + '</Stock_ReservedStockQty>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Stock_ReservedStockInOrderQty>' + @Stock_ReservedStockInOrderQty + '</Stock_ReservedStockInOrderQty>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Stock_StockInOrderQty>' + @Stock_StockInOrderQty + '</Stock_StockInOrderQty>' + @CrLf
		IF @Stock_LastUpdatedStockCount = ''
			SET @FileBuffer = @FileBuffer + '			<Stock_LastUpdatedStockCount xsi:nil="true"/>' + @CrLf
		ELSE
			SET @FileBuffer = @FileBuffer + '			<Stock_LastUpdatedStockCount>' + @Stock_LastUpdatedStockCount + '</Stock_LastUpdatedStockCount>' + @CrLf

		IF @Stock_LastUpdatedSoldDate = ''
			SET @FileBuffer = @FileBuffer + '			<Stock_LastUpdatedSoldDate xsi:nil="true"/>' + @CrLf
		ELSE
			SET @FileBuffer = @FileBuffer + '			<Stock_LastUpdatedSoldDate>' + @Stock_LastUpdatedSoldDate + '</Stock_LastUpdatedSoldDate>' + @CrLf
		
		IF @Stock_LastPurchased = ''
			SET @FileBuffer = @FileBuffer + '			<Stock_LastPurchased xsi:nil="true"/>' + @CrLf
		ELSE
			SET @FileBuffer = @FileBuffer + '			<Stock_LastPurchased>' + @Stock_LastPurchased + '</Stock_LastPurchased>' + @CrLf
		
		IF @Stock_LastReceived = ''
			SET @FileBuffer = @FileBuffer + '			<Stock_LastReceived xsi:nil="true"/>' + @CrLf
		ELSE
			SET @FileBuffer = @FileBuffer + '			<Stock_LastReceived>' + @Stock_LastReceived + '</Stock_LastReceived>' + @CrLf
		IF @Stock_ModifiedDate = ''
			SET @FileBuffer = @FileBuffer + '			<Stock_ModifiedDate xsi:nil="true"/>' + @CrLf
		ELSE
			SET @FileBuffer = @FileBuffer + '			<Stock_ModifiedDate>' + @Stock_ModifiedDate + '</Stock_ModifiedDate>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_TransactionCounter>' + @Adj_TransactionCounter + '</Adj_TransactionCounter>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_AdjustmentDate>' + @Adj_AdjustmentDate + '</Adj_AdjustmentDate>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_StockAdjReasonNo>' + @Adj_StockAdjReasonNo + '</Adj_StockAdjReasonNo>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_StockAdjType>' + @Adj_StockAdjType + '</Adj_StockAdjType>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_AdjustmentQty>' + @Adj_AdjustmentQty + '</Adj_AdjustmentQty>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_NetPrice>' + @Adj_NetPrice + '</Adj_NetPrice>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_DerivedNetCostAmount>' + @Adj_DerivedNetCostAmount + '</Adj_DerivedNetCostAmount>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_NetSalesPrice>' + @Adj_NetSalesPrice + '</Adj_NetSalesPrice>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_SalesPrice>' + @Adj_SalesPrice + '</Adj_SalesPrice>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_UserID>' + @Adj_UserID + '</Adj_UserID>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_LinkQty>' + @Adj_LinkQty + '</Adj_LinkQty>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_LinkArticleID xsi:nil="true"/>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_LinkGtinNo xsi:nil="true"/>' + @CrLf
		IF @Adj_StockCountNo = ''
			SET @FileBuffer = @FileBuffer + '			<Adj_StockCountNo xsi:nil="true"/>' + @CrLf
		ELSE
			SET @FileBuffer = @FileBuffer + '			<Adj_StockCountNo>' + @Adj_StockCountNo + '</Adj_StockCountNo>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_AdjustmentRefNo>' + @Adj_AdjustmentRefNo + '</Adj_AdjustmentRefNo>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Stock_ExportTimestamp>' + @Stock_ExportTimestamp + '</Stock_ExportTimestamp>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_IsMaster>' + @Adj_IsMaster + '</Adj_IsMaster>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_LotNumber>' + @Adj_LotNumber + '</Adj_LotNumber>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_SupplierID>' + @Adj_SupplierID + '</Adj_SupplierID>' + @CrLf
		SET @FileBuffer = @FileBuffer + '			<Adj_SupplierType>' + @Adj_SupplierType + '</Adj_SupplierType>' + @CrLf
		SET @FileBuffer = @FileBuffer + '		</StockTransaction>' + @CrLf
		
		FETCH NEXT FROM StockCursor
		INTO	
			@Stock_StoreID,
			@Stock_ArticleID,
			@Stock_GtinNo,
			@Stock_InStockQty,
			@Stock_BStockQty,
			@Stock_OnDisplayQty,
			@Stock_HomeLoanQty,
			@Stock_OnServiceQty,
			@Stock_StockInTransitQty,
			@Stock_NotDeliveredQty,
			@Stock_ReservedStockQty,
			@Stock_ReservedStockInOrderQty,
			@Stock_StockInOrderQty,
			@Stock_LastUpdatedStockCount,
			@Stock_LastUpdatedSoldDate,
			@Stock_LastPurchased,
			@Stock_LastReceived,
			@Stock_ModifiedDate,
			@Adj_TransactionCounter,
			@Adj_AdjustmentDate,
			@Adj_StockAdjReasonNo,
			@Adj_StockAdjType,
			@Adj_AdjustmentQty,
			@Adj_NetPrice,
			@Adj_DerivedNetCostAmount,
			@Adj_NetSalesPrice,
			@Adj_SalesPrice,
			@Adj_LinkQty,
			@Adj_LinkArticleID,
			@Adj_LinkGtinNo,
			@Adj_StockCountNo,
			@Adj_AdjustmentRefNo,
			@Stock_ExportTimestamp,
			@Adj_IsMaster,
			@Adj_UserId,
			@Adj_LotNumber,
			@Adj_SupplierID,
			@Adj_SupplierType

		Set @BufferFill = @BufferFill + 1
		SET @NumberOfRecords = @NumberOfRecords + 1
	
		if @BufferFill >= @MaxFill
		BEGIN
			SET @StrMsg = 'Writing ' + CAST(@BufferFill AS varchar) + ' records (' + CAST(LEN(@FileBuffer) AS varchar) + ' bytes)'
			RAISERROR(@StrMsg, 0, 42) WITH NOWAIT;	
			Exec dbo.spWriteStringToFile @FileBuffer, @PathAndFilename, 1
			Set @FileBuffer = ''
			Set @BufferFill = 0
		End

	END

	SET @StrMsg = 'Writing ' + CAST(@BufferFill AS varchar) + ' records'
	RAISERROR(@StrMsg, 0, 42) WITH NOWAIT;

	SET @FileBuffer = @FileBuffer + '	</StockTransactions>' + @CrLf
	SET @FileBuffer = @FileBuffer + '</RS>' + @CrLf
	EXEC dbo.spWriteStringToFile @FileBuffer, @PathAndFilename, 1

	SET @StrMsg = 'Total number of records: ' + CAST(@NumberOfRecords AS varchar)
	RAISERROR(@StrMsg, 0, 42) WITH NOWAIT;

	INSERT VRPS_ExportedTransactions (ConversationID, FromTransactionCounter, ToTransactionCounter, RecordCreated)
	VALUES (@ConversationID, @FromTransactionCounter, @ToTransactionCounter, GETDATE())

	CLOSE StockCursor
	DEALLOCATE StockCursor

END

