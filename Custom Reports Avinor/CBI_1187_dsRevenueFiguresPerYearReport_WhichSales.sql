USE [BI_Mart]
GO

/****** Object:  StoredProcedure [dbo].[usp_CBI_1187_dsRevenueFiguresPerYearReport_WhichSales]    Script Date: 28.06.2018 13:36:32 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


/*DECLARE @StoreOrGroupNo AS VARCHAR(MAX) = 9998    
	,@DateFrom AS  DATE = '2017-01-01' 
	,@DateTo AS  DATE  = '2017-01-31'
   ,@ReportType SMALLINT =0-- 0 all flights, 1 departure, 2 arrival--, 3 extra 
	,@FlightNo VARCHAR(max) --list of flight no
	,@AirportCodes VARCHAR(max) --list of arirport codes	
	,@ArticleSelection AS  VARCHAR(MAX) 
	*/
CREATE  PROCEDURE [dbo].[usp_CBI_1187_dsRevenueFiguresPerYearReport_WhichSales] (
	 @StoreOrGroupNo AS VARCHAR(MAX)    
	,@DateFrom AS  DATE  
	,@DateTo AS  DATE  
    ,@ReportType SMALLINT -- 0 all flights, 1 departure, 2 arrival--, 3 extra 
	,@FlightNo VARCHAR(MAX) --list of flight no
	,@AirportCodes VARCHAR(MAX) --list of arirport codes	
	,@ArticleSelection AS  VARCHAR(MAX) 
	,@WhichSales SMALLINT	-- 0 all sales, 1 Pick And Collect, 2 all sales except Pick And Collect
)
AS
BEGIN

SET NOCOUNT ON;

----------------------------------------------------------------------
--Prepare input
----------------------------------------------------------------------

IF RTRIM(LTRIM(@AirportCodes)) = '' SET @AirportCodes = NULL
IF RTRIM(LTRIM(@FlightNo)) = '' SET @FlightNo = NULL

DECLARE @flights TABLE(
FlightNo VARCHAR(MAX))

INSERT INTO @flights
SELECT ParameterValue FROM [dbo].[ufn_RBI_SplittParameterString](@FlightNo,',''')

DECLARE @codes TABLE(
AirportCode VARCHAR(MAX))

INSERT INTO @codes
SELECT ParameterValue FROM [dbo].[ufn_RBI_SplittParameterString](@AirportCodes,',''')

DECLARE @articles TABLE(
ArticleId VARCHAR(MAX))

INSERT INTO @articles
SELECT ParameterValue FROM [dbo].[ufn_RBI_SplittParameterString](@ArticleSelection,',''')

--------

DECLARE @ThisYear INT = (SELECT Year FROM RBIM.Dim_Date WHERE FullDate = @DateFrom)

DECLARE @DateFromIdx INT = cast(convert(varchar(8),@DateFrom, 112) as integer)
DECLARE @DateToIdx INT = cast(convert(varchar(8),@DateTo, 112) as integer)
DECLARE @DateFromIdxStartThisYear INT = (SELECT MIN(DateIdx) FROM RBIM.Dim_Date WHERE Year = @ThisYear)

DECLARE @DateFromIdxLastYear INT = (SELECT DateIdx FROM RBIM.Dim_Date WHERE MonthNumberOfYear = SUBSTRING(convert(varchar(10),@DateFromIdx), 5,2) AND DayNumberOfMonth = RIGHT(@DateFromIdx, 2) AND Year = @ThisYear-1)
DECLARE @DateToIdxLastYear INT = (SELECT DateIdx FROM RBIM.Dim_Date WHERE MonthNumberOfYear = SUBSTRING(convert(varchar(10),@DateToIdx), 5,2) AND DayNumberOfMonth = RIGHT(@DateToIdx, 2) AND Year = @ThisYear-1)
DECLARE @DateFromIdxStartLastYear INT = (SELECT MIN(DateIdx) FROM RBIM.Dim_Date WHERE Year = @ThisYear-1)


----------------------------------------------------------------------
--Find stores
----------------------------------------------------------------------

DECLARE @stores TABLE(
StoreIdx INT,
StoreId VARCHAR(MAX),
StoreName VARCHAR(MAX))

INSERT INTO @stores
SELECT DISTINCT ds.StoreIdx, ds.StoreId, ds.StoreName
FROM RBIM.Dim_Store ds (NOLOCK)
LEFT JOIN ( SELECT ParameterValue FROM [dbo].[ufn_RBI_SplittParameterString](@StoreOrGroupNo,',''')) n  ON n.ParameterValue IN (
						ds.Lev1RegionGroupNo ,ds.Lev2RegionGroupNo,ds.Lev3RegionGroupNo,ds.Lev4RegionGroupNo,ds.Lev5RegionGroupNo,				--Region
						ds.Lev1LegalGroupNo,ds.Lev2LegalGroupNo,ds.Lev3LegalGroupNo,ds.Lev4LegalGroupNo,ds.Lev5LegalGroupNo,					--Legal
						ds.Lev1ChainGroupNo,ds.Lev2ChainGroupNo,ds.Lev3ChainGroupNo,ds.Lev4ChainGroupNo,ds.Lev5ChainGroupNo,					--Chain
						ds.Lev1DistrictGroupNo,ds.Lev2DistrictGroupNo,ds.Lev3DistrictGroupNo,ds.Lev4DistrictGroupNo,ds.Lev5DistrictGroupNo,		--District
						ds.StoreId) 
WHERE n.ParameterValue IS NOT NULL AND ds.isCurrent=1 -- ds.IsCurrentStore=1 OLD


IF ( @WhichSales = 0 )		-- 0 = Alt salg dvs inkluder P&C orginal spøring
BEGIN


----------------------------------------------------------------------
--Select
----------------------------------------------------------------------
;WITH flightReceipts AS (
	SELECT 
		FLOOR(receiptidx/1000) AS ReceiptHeadIdx,
		ds.StoreName, 
		se.ReceiptDateIdx, 
		CASE transtypevaluetxt4
						WHEN 'D' THEN transtypevaluetxt1 + ' - ' + se.TransTypeValueTxt3 
						WHEN 'A' THEN transtypevaluetxt1 + ' - ' + se.TransTypeValueTxt2	
						ELSE 	transtypevaluetxt1	
				END AS FlightNo,
			CASE 
					WHEN (transtypevaluetxt4 = 'D' OR transtypevaluetxt1 = 'AVN001') THEN 'Avgang' 
					WHEN (transtypevaluetxt4 = 'A' OR transtypevaluetxt1 = 'AVN000') THEN 'Ankomst'
					--WHEN '' THEN 'Ekstra'	
					ELSE 	''	
			END  AS FlightType
	FROM RBIM.Cov_customersalesevent se (NOLOCK)
	JOIN RBIM.Dim_TransType (NOLOCK) tt ON tt.TransTypeIdx = Se.TransTypeIdx
	JOIN RBIM.Dim_Date dd (NOLOCK) ON dd.dateidx = se.receiptdateidx
	JOIN @stores ds ON ds.storeidx = se.storeidx
	WHERE tt.transtypeId = 90403									
	AND (se.ReceiptDateIdx BETWEEN @DateFromIdx AND @DateToIdx
			OR se.ReceiptDateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear
			OR se.ReceiptDateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx
			OR se.ReceiptDateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear)
	AND (	@ReportType = 0 -- all flights
			OR (@ReportType = 1 AND (se.TransTypeValueTxt4 = 'D' OR se.TransTypeValueTxt1 = 'AVN001')) -- departure flights
			OR (@ReportType = 2 AND (se.TransTypeValueTxt4 = 'A' OR se.TransTypeValueTxt1 = 'AVN000')) -- arrival flights
			--OR (@ReportType = 3 AND se.TransTypeValueTxt4 = '') -- extra flights
	 )
	AND (	@AirportCodes IS NULL  --no filtering on airport codes
			OR (se.TransTypeValueTxt2  IN (SELECT AirportCode FROM @codes)) 
			OR (se.TransTypeValueTxt3  IN (SELECT AirportCode FROM @codes)) 
		 )
	AND (	@FlightNo IS NULL  --no filtering on flight no
			OR (se.TransTypeValueTxt1  IN (SELECT FlightNo FROM @flights)) 
		 )
),
SalesReceipts AS (
SELECT 
		FLOOR(f.ReceiptIdx/1000) AS ReceiptHeadIdx,
		f.ReceiptId,
		f.ReceiptDateIdx,
		da.ArticleId,
		da.ArticleName,
		da.Lev1ArticleHierarchyId,
		da.Lev1ArticleHierarchyName,
		(f.QuantityOfArticlesSold-f.QuantityOfArticlesInReturn) AS NoOfArticlesSold,
		(f.SalesAmountExclVat+f.ReturnAmountExclVat) AS Revenue,
		f.NumberOfCustomers AS NoOfCustomers
	FROM RBIM.Fact_ReceiptRowSalesAndReturn f (NOLOCK)
	JOIN RBIM.Dim_Article da (NOLOCK) ON da.ArticleIdx = f.ArticleIdx
	JOIN @stores ds  ON ds.storeidx = f.storeidx
	WHERE (f.ReceiptDateIdx BETWEEN @DateFromIdx AND @DateToIdx
			OR f.ReceiptDateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear
			OR f.ReceiptDateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx
			OR f.ReceiptDateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear)
	--AND (f.QuantityOfArticlesSold-f.QuantityOfArticlesInReturn) <> 0 
	--AND (f.SalesAmountExclVat+f.ReturnAmountExclVat) <> 0
), 

SalesInPeriod AS (
SELECT  
SALES.Lev1ArticleHierarchyName,
SUM(SALES.NoOfArticlesSold) AS NoOfArticlesSold,
SUM(SALES.Revenue) AS Revenue,
SUM(SALES.NoOfCustomers) AS NoOfCustomers
FROM  
(
	SELECT 
		ReceiptHeadIdx
	FROM flightReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdx AND @DateToIdx	
) FLIGHT
INNER JOIN 
(
	SELECT 
		ReceiptHeadIdx,
		ReceiptId,
		ArticleId,
		Lev1ArticleHierarchyName,
		NoOfArticlesSold,
		Revenue,
		NoOfCustomers
	FROM SalesReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdx AND @DateToIdx							
	
) SALES
ON FLIGHT.ReceiptHeadIdx = SALES.ReceiptHeadIdx 
WHERE --Filter on article selection
   (@ArticleSelection IS NULL OR SALES.ArticleID IN (SELECT ArticleId FROM @articles))
GROUP BY 
SALES.Lev1ArticleHierarchyName
--HAVING SUM(Revenue) <> 0
),

salesInPeriodLastYear AS (
SELECT  
SALES.Lev1ArticleHierarchyName,
SUM(SALES.NoOfArticlesSold) AS NoOfArticlesSold_lastYear,
SUM(SALES.Revenue) AS Revenue_lastYear,
SUM(SALES.NoOfCustomers) AS NoOfCustomers_lastYear
FROM  
(
	SELECT 
		ReceiptHeadIdx
	FROM flightReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear
) FLIGHT
INNER JOIN 
(
	SELECT 
		ReceiptHeadIdx,
		ReceiptId,
		ArticleId,
		Lev1ArticleHierarchyName,
		NoOfArticlesSold,
		Revenue,
		NoOfCustomers
	FROM SalesReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear						
	
) SALES
ON FLIGHT.ReceiptHeadIdx = SALES.ReceiptHeadIdx 
WHERE --Filter on article selection
   (@ArticleSelection IS NULL OR SALES.ArticleID IN (SELECT ArticleId FROM @articles))
GROUP BY 
SALES.Lev1ArticleHierarchyName
--HAVING SUM(Revenue) <> 0
) 
, salesYtd AS (
SELECT  
SALES.Lev1ArticleHierarchyName,
SUM(SALES.NoOfArticlesSold) AS NoOfArticlesSold_ytd,
SUM(SALES.Revenue) AS Revenue_ytd,
SUM(SALES.NoOfCustomers) AS NoOfCustomers_ytd
FROM  
(
	SELECT 
		ReceiptHeadIdx
	FROM flightReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx
) FLIGHT
INNER JOIN 
(
	SELECT 
		ReceiptHeadIdx,
		ReceiptId,
		ArticleId,
		Lev1ArticleHierarchyName,
		NoOfArticlesSold,
		Revenue,
		NoOfCustomers
	FROM SalesReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx						
	
) SALES
ON FLIGHT.ReceiptHeadIdx = SALES.ReceiptHeadIdx 
WHERE --Filter on article selection
   (@ArticleSelection IS NULL OR SALES.ArticleID IN (SELECT ArticleId FROM @articles))
GROUP BY 
SALES.Lev1ArticleHierarchyName
--HAVING SUM(Revenue) <> 0
)
, SalesLastYTD AS (
SELECT  
SALES.Lev1ArticleHierarchyName,
SUM(SALES.NoOfArticlesSold) AS NoOfArticlesSold_lastYTD,
SUM(SALES.Revenue) AS Revenue_lastYTD,
SUM(SALES.NoOfCustomers) AS NoOfCustomers_lastYTD
FROM  
(
	SELECT 
		ReceiptHeadIdx
	FROM flightReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear
) FLIGHT
INNER JOIN 
(
	SELECT 
		ReceiptHeadIdx,
		ReceiptId,
		ArticleId,
		Lev1ArticleHierarchyName,
		NoOfArticlesSold,
		Revenue,
		NoOfCustomers
	FROM SalesReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear						
	
) SALES
ON FLIGHT.ReceiptHeadIdx = SALES.ReceiptHeadIdx 
WHERE --Filter on article selection
   (@ArticleSelection IS NULL OR SALES.ArticleID IN (SELECT ArticleId FROM @articles))
GROUP BY 
SALES.Lev1ArticleHierarchyName
--HAVING SUM(Revenue) <> 0
)/*
SELECT * FROM SalesInPeriod s
JOIN SalesYTD sytd ON sytd.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesInPeriodLastYear sl ON sl.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesLastYTD slytd ON slytd.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
*/
,Totals AS (
SELECT 
NULL AS Lev1ArticleHierarchyName
, SUM(NoOfCustomers)  AS NoOfCustomers
, SUM(NoOfCustomers_YTD)  AS NoOfCustomers_YTD
, SUM(NoOfCustomers_lastYear) AS NoOfCustomers_lastYear
, SUM(NoOfCustomers_lastYTD) AS NoOfCustomers_lastYTD
, SUM(Revenue) AS Revenue
, SUM(Revenue_YTD) AS Revenue_YTD
, SUM(Revenue_lastYear) AS Revenue_lastYear
, SUM(Revenue_lastYTD) AS Revenue_lastYTD
, CAST(SUM(NoOfArticlesSold) AS DECIMAL) AS NoOfArticlesSold
, CAST(SUM(NoOfArticlesSold_YTD) AS DECIMAL) AS NoOfArticlesSold_YTD
, CAST(SUM(NoOfArticlesSold_lastYear) AS DECIMAL) AS NoOfArticlesSold_lastYear
, CAST(SUM(NoOfArticlesSold_lastYTD) AS DECIMAL) AS NoOfArticlesSold_lastYTD
FROM SalesInPeriod s
JOIN SalesYTD sytd ON sytd.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesInPeriodLastYear sl ON sl.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesLastYTD slytd ON slytd.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
), 
Total AS (
SELECT s.Lev1ArticleHierarchyName
, s.Revenue
, CAST(s.NoOfArticlesSold AS DECIMAL) AS NoOfArticlesSold
, (SELECT NoOfCustomers FROM Totals) AS NoOfCustomers
, sytd.Revenue_YTD AS Revenue_YTD
, CASE WHEN sytd.NoOfArticlesSold_YTD = 0 THEN NULL ELSE CAST(sytd.NoOfArticlesSold_YTD AS DECIMAL) END AS NoOfArticlesSold_YTD
, CASE WHEN t.NoOfCustomers_YTD = 0 THEN NULL ELSE t.NoOfCustomers_YTD END AS NoOfCustomers_YTD
, sl.Revenue_lastYear AS Revenue_lastYear
, CASE WHEN sl.NoOfArticlesSold_lastYear = 0 THEN NULL ELSE CAST(sl.NoOfArticlesSold_lastYear AS DECIMAL) END AS NoOfArticlesSold_lastYear
, CASE WHEN t.NoOfCustomers_lastYear = 0 THEN NULL ELSE t.NoOfCustomers_lastYear END AS NoOfCustomers_lastYear
, slytd.Revenue_lastYTD AS Revenue_lastYTD
, CASE WHEN slytd.NoOfArticlesSold_lastYTD = 0 THEN NULL ELSE CAST(slytd.NoOfArticlesSold_lastYTD AS DECIMAL) END AS NoOfArticlesSold_lastYTD
, CASE WHEN t.NoOfCustomers_lastYTD = 0 THEN NULL ELSE t.NoOfCustomers_lastYTD END AS NoOfCustomers_lastYTD
FROM SalesInPeriod s
JOIN SalesYTD sytd ON sytd.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesInPeriodLastYear sl ON sl.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesLastYTD slytd ON slytd.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
JOIN Totals t ON 1=1
)

SELECT
 t.Lev1ArticleHierarchyName
, NULL AS total
, x.Data
, CASE WHEN x.periode = 0 THEN NULL ELSE x.periode END AS periode
, CASE WHEN x.ytd = 0 THEN NULL ELSE x.ytd END AS ytd
, CASE WHEN x.periode_lastYear = 0 THEN NULL ELSE x.periode_lastYear END AS periode_lastYear
, CASE WHEN x.ytd_lastYear = 0 THEN NULL ELSE x.ytd_lastYear END AS ytd_lastYear
FROM Total t
CROSS APPLY (
	VALUES
         ('1 Revenue' , t.Revenue, t.Revenue_YTD, t.Revenue_lastYear, t.Revenue_lastYTD),
         ('2 NoOfArticles' , t.NoOfArticlesSold, t.NoOfArticlesSold_YTD, t.NoOfArticlesSold_lastYear, t.NoOfArticlesSold_lastYTD),
        -- ('3 NoOfCustomers' , t.NoOfCustomers, t.NoOfCustomers_YTD, t.NoOfCustomers_lastYear, t.NoOfCustomers_lastYTD),
			('4 RevenuePerCustomer', (t.Revenue/t.NoOfCustomers) , (t.Revenue_YTD/t.NoOfCustomers_YTD), (t.Revenue_lastYear/t.NoOfCustomers_lastYear), (t.Revenue_lastYTD/t.NoOfCustomers_lastYTD)),
			('5 ItemsPerCustomer', (t.NoOfArticlesSold/t.NoOfCustomers),(t.NoOfArticlesSold_YTD/t.NoOfCustomers_YTD),(t.NoOfArticlesSold_lastYear/t.NoOfCustomers_lastYear),(t.NoOfArticlesSold_lastYTD/t.NoOfCustomers_lastYTD)),
			('6 PricePerItem', (t.Revenue/t.NoOfArticlesSold), (t.Revenue_YTD/t.NoOfArticlesSold_YTD),(t.Revenue_lastYear/t.NoOfArticlesSold_lastYear),(t.Revenue_lastYTD/t.NoOfArticlesSold_lastYTD) )
  ) x (Data, periode, ytd, periode_lastYear, ytd_lastYear)
WHERE t.Revenue <> 0

   UNION 

	SELECT
	'Total' AS Lev1ArticleHierarchyName
	, 'Total' AS Total
	, x.Data
	, CASE WHEN x.periode = 0 THEN NULL ELSE x.periode END AS periode
	, CASE WHEN x.ytd = 0 THEN NULL ELSE x.ytd END AS ytd
	, CASE WHEN x.periode_lastYear = 0 THEN NULL ELSE x.periode_lastYear END AS periode_lastYear
	, CASE WHEN x.ytd_lastYear = 0 THEN NULL ELSE x.ytd_lastYear END AS ytd_lastYear
	FROM Totals t
	CROSS APPLY (
			VALUES
				('1 Revenue' , t.Revenue, t.Revenue_YTD, t.Revenue_lastYear, t.Revenue_lastYTD),
				('2 NoOfArticles' , t.NoOfArticlesSold, t.NoOfArticlesSold_YTD, t.NoOfArticlesSold_lastYear, t.NoOfArticlesSold_lastYTD),
			    ('3 NoOfCustomers' , t.NoOfCustomers, t.NoOfCustomers_YTD, t.NoOfCustomers_lastYear, t.NoOfCustomers_lastYTD),
				('4 RevenuePerCustomer', (t.Revenue/t.NoOfCustomers) , (t.Revenue_YTD/t.NoOfCustomers_YTD), (t.Revenue_lastYear/t.NoOfCustomers_lastYear), (t.Revenue_lastYTD/t.NoOfCustomers_lastYTD)),
				('5 ItemsPerCustomer', (t.NoOfArticlesSold/t.NoOfCustomers),(t.NoOfArticlesSold_YTD/t.NoOfCustomers_YTD),(t.NoOfArticlesSold_lastYear/t.NoOfCustomers_lastYear),(t.NoOfArticlesSold_lastYTD/t.NoOfCustomers_lastYTD)),
				('6 PricePerItem', (t.Revenue/t.NoOfArticlesSold), (t.Revenue_YTD/t.NoOfArticlesSold_YTD),(t.Revenue_lastYear/t.NoOfArticlesSold_lastYear),(t.Revenue_lastYTD/t.NoOfArticlesSold_lastYTD) )
	  ) x (Data, periode, ytd, periode_lastYear, ytd_lastYear)

ORDER BY data, Total, t.Lev1ArticleHierarchyName ASC


END -- 0 = Alt salg dvs inkluder P&C orginal spøring

IF ( @WhichSales = 1 )		-- 1 Pick And Collect
BEGIN

;WITH FlightPC AS (
	SELECT 
		APACO.orderID AS ReceiptHeadIdx,	--FLOOR(f.ReceiptIdx/1000) AS ReceiptHeadIdx,
		APACO.orderID AS ReceiptId,			--f.ReceiptId,
		dd.DateIdx    AS ReceiptDateIdx
	FROM CBIM.Agg_PickAndCollectOrders AS APACO (nolock) --P&C
	--INNER JOIN CBIM.Agg_PickAndCollectOrderLines AS APACOL (nolock) ON APACOL.OrderID = APACO.OrderID
	--inner join RBIM.Dim_Gtin dg (nolock)							ON dg.Gtin = APACOL.ArticleEan and dg.StatusId=1	--1=Aktiv,9=Slettet ...
	--inner join RBIM.Cov_ArticleGtin ag (nolock)						ON ag.GtinIdx = dg.GtinIdx
	--inner join RBIM.Dim_Article da (nolock)							ON da.ArticleIdx = ag.ArticleIdx and da.isCurrent=1
	INNER JOIN RBIM.Dim_Date AS DD ON (convert(date,APACO.PaymentSuccessTimeStamp,103)) = dd.FullDate
	JOIN @stores ds  ON ds.StoreId = APACO.StoreId
	WHERE (dd.DateIdx BETWEEN @DateFromIdx AND @DateToIdx
			OR dd.DateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear
			OR dd.DateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx
			OR dd.DateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear)
),
SalesPC AS (
SELECT 
		APACO.orderID AS ReceiptHeadIdx,	--FLOOR(f.ReceiptIdx/1000) AS ReceiptHeadIdx,
		APACO.orderID AS ReceiptId,			--f.ReceiptId,
		dd.DateIdx    AS ReceiptDateIdx,
		da.ArticleId,
		da.ArticleName,
		da.Lev1ArticleHierarchyId,
		da.Lev1ArticleHierarchyName,
		APACOL.ReceivedQty AS NoOfArticlesSold,
		APACOL.ArticleDeliveredPrice AS Revenue,
		NoOfCustomers = ( SELECT COUNT(*) FROM CBIM.Agg_PickAndCollectOrders AS APACO (nolock) --P&C
						--INNER JOIN CBIM.Agg_PickAndCollectOrderLines AS APACOL (nolock) ON APACOL.OrderID = APACO.OrderID
						INNER JOIN RBIM.Dim_Date AS DD ON (convert(date,APACO.PaymentSuccessTimeStamp,103)) = dd.FullDate
						JOIN @stores ds  ON ds.StoreId = APACO.StoreId
						WHERE (dd.DateIdx BETWEEN @DateFromIdx AND @DateToIdx
						OR dd.DateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear
						OR dd.DateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx
						OR dd.DateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear)
						)
	FROM CBIM.Agg_PickAndCollectOrders AS APACO (nolock) --P&C
	INNER JOIN CBIM.Agg_PickAndCollectOrderLines AS APACOL (nolock) ON APACOL.OrderID = APACO.OrderID
	inner join RBIM.Dim_Gtin dg (nolock)							ON dg.Gtin = APACOL.ArticleEan and dg.StatusId=1	--1=Aktiv,9=Slettet ...
	inner join RBIM.Cov_ArticleGtin ag (nolock)						ON ag.GtinIdx = dg.GtinIdx
	inner join RBIM.Dim_Article da (nolock)							ON da.ArticleIdx = ag.ArticleIdx and da.isCurrent=1
	INNER JOIN RBIM.Dim_Date AS DD ON (convert(date,APACO.PaymentSuccessTimeStamp,103)) = dd.FullDate
	JOIN @stores ds  ON ds.StoreId = APACO.StoreId
	WHERE (dd.DateIdx BETWEEN @DateFromIdx AND @DateToIdx
			OR dd.DateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear
			OR dd.DateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx
			OR dd.DateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear)
)
, SalesInPeriod AS (
SELECT  
SALES.Lev1ArticleHierarchyName,
SUM(SALES.NoOfArticlesSold) AS NoOfArticlesSold,
SUM(SALES.Revenue) AS Revenue,
MAX(SALES.NoOfCustomers) AS NoOfCustomers
FROM  
(
	SELECT 
		ReceiptHeadIdx
	FROM FlightPC--flightReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdx AND @DateToIdx	
) FLIGHT
INNER JOIN 
(
	SELECT 
		ReceiptHeadIdx,
		ReceiptId,
		ArticleId,
		Lev1ArticleHierarchyName,
		NoOfArticlesSold,
		Revenue,
		NoOfCustomers
	FROM SalesPC--SalesReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdx AND @DateToIdx							
	
) SALES
ON FLIGHT.ReceiptHeadIdx = SALES.ReceiptHeadIdx 
WHERE --Filter on article selection
   (@ArticleSelection IS NULL OR SALES.ArticleID IN (SELECT ArticleId FROM @articles))
GROUP BY 
SALES.Lev1ArticleHierarchyName
--HAVING SUM(Revenue) <> 0
),

salesInPeriodLastYear AS (
SELECT  
SALES.Lev1ArticleHierarchyName,
SUM(SALES.NoOfArticlesSold) AS NoOfArticlesSold_lastYear,
SUM(SALES.Revenue) AS Revenue_lastYear,
MAX(SALES.NoOfCustomers) AS NoOfCustomers_lastYear
FROM  
(
	SELECT 
		ReceiptHeadIdx
	FROM FlightPC--flightReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear
) FLIGHT
INNER JOIN 
(
	SELECT 
		ReceiptHeadIdx,
		ReceiptId,
		ArticleId,
		Lev1ArticleHierarchyName,
		NoOfArticlesSold,
		Revenue,
		NoOfCustomers
	FROM SalesPC--SalesReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear						
	
) SALES
ON FLIGHT.ReceiptHeadIdx = SALES.ReceiptHeadIdx 
WHERE --Filter on article selection
   (@ArticleSelection IS NULL OR SALES.ArticleID IN (SELECT ArticleId FROM @articles))
GROUP BY 
SALES.Lev1ArticleHierarchyName
--HAVING SUM(Revenue) <> 0
) , 

salesYtd AS (
SELECT  
SALES.Lev1ArticleHierarchyName,
SUM(SALES.NoOfArticlesSold) AS NoOfArticlesSold_ytd,
SUM(SALES.Revenue) AS Revenue_ytd,
MAX(SALES.NoOfCustomers) AS NoOfCustomers_ytd
FROM  
(
	SELECT 
		ReceiptHeadIdx
	FROM FlightPC--flightReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx
) FLIGHT
INNER JOIN 
(
	SELECT 
		ReceiptHeadIdx,
		ReceiptId,
		ArticleId,
		Lev1ArticleHierarchyName,
		NoOfArticlesSold,
		Revenue,
		NoOfCustomers
	FROM SalesPC--SalesReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx						
	
) SALES
ON FLIGHT.ReceiptHeadIdx = SALES.ReceiptHeadIdx 
WHERE --Filter on article selection
   (@ArticleSelection IS NULL OR SALES.ArticleID IN (SELECT ArticleId FROM @articles))
GROUP BY 
SALES.Lev1ArticleHierarchyName
--HAVING SUM(Revenue) <> 0
), 

SalesLastYTD AS (
SELECT  
SALES.Lev1ArticleHierarchyName,
SUM(SALES.NoOfArticlesSold) AS NoOfArticlesSold_lastYTD,
SUM(SALES.Revenue) AS Revenue_lastYTD,
MAX(SALES.NoOfCustomers) AS NoOfCustomers_lastYTD
FROM  
(
	SELECT 
		ReceiptHeadIdx
	FROM FlightPC--flightReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear
) FLIGHT
INNER JOIN 
(
	SELECT 
		ReceiptHeadIdx,
		ReceiptId,
		ArticleId,
		Lev1ArticleHierarchyName,
		NoOfArticlesSold,
		Revenue,
		NoOfCustomers
	FROM SalesPC--SalesReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear						
	
) SALES
ON FLIGHT.ReceiptHeadIdx = SALES.ReceiptHeadIdx 
WHERE --Filter on article selection
   (@ArticleSelection IS NULL OR SALES.ArticleID IN (SELECT ArticleId FROM @articles))
GROUP BY 
SALES.Lev1ArticleHierarchyName
--HAVING SUM(Revenue) <> 0
)/*
SELECT * FROM SalesInPeriod s
JOIN SalesYTD sytd ON sytd.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesInPeriodLastYear sl ON sl.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesLastYTD slytd ON slytd.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
*/
,

Totals AS (
SELECT 
NULL AS Lev1ArticleHierarchyName
, MAX(NoOfCustomers)  AS NoOfCustomers
, MAX(NoOfCustomers_YTD)  AS NoOfCustomers_YTD
, MAX(NoOfCustomers_lastYear) AS NoOfCustomers_lastYear
, MAX(NoOfCustomers_lastYTD) AS NoOfCustomers_lastYTD
, SUM(Revenue) AS Revenue
, SUM(Revenue_YTD) AS Revenue_YTD
, SUM(Revenue_lastYear) AS Revenue_lastYear
, SUM(Revenue_lastYTD) AS Revenue_lastYTD
, CAST(SUM(NoOfArticlesSold) AS DECIMAL) AS NoOfArticlesSold
, CAST(SUM(NoOfArticlesSold_YTD) AS DECIMAL) AS NoOfArticlesSold_YTD
, CAST(SUM(NoOfArticlesSold_lastYear) AS DECIMAL) AS NoOfArticlesSold_lastYear
, CAST(SUM(NoOfArticlesSold_lastYTD) AS DECIMAL) AS NoOfArticlesSold_lastYTD
FROM SalesInPeriod s
JOIN SalesYTD sytd ON sytd.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesInPeriodLastYear sl ON sl.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesLastYTD slytd ON slytd.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
), 
Total AS (
SELECT s.Lev1ArticleHierarchyName
, s.Revenue
, CAST(s.NoOfArticlesSold AS DECIMAL) AS NoOfArticlesSold
, (SELECT NoOfCustomers FROM Totals) AS NoOfCustomers
, sytd.Revenue_YTD AS Revenue_YTD
, CASE WHEN sytd.NoOfArticlesSold_YTD = 0 THEN NULL ELSE CAST(sytd.NoOfArticlesSold_YTD AS DECIMAL) END AS NoOfArticlesSold_YTD
, CASE WHEN t.NoOfCustomers_YTD = 0 THEN NULL ELSE t.NoOfCustomers_YTD END AS NoOfCustomers_YTD
, sl.Revenue_lastYear AS Revenue_lastYear
, CASE WHEN sl.NoOfArticlesSold_lastYear = 0 THEN NULL ELSE CAST(sl.NoOfArticlesSold_lastYear AS DECIMAL) END AS NoOfArticlesSold_lastYear
, CASE WHEN t.NoOfCustomers_lastYear = 0 THEN NULL ELSE t.NoOfCustomers_lastYear END AS NoOfCustomers_lastYear
, slytd.Revenue_lastYTD AS Revenue_lastYTD
, CASE WHEN slytd.NoOfArticlesSold_lastYTD = 0 THEN NULL ELSE CAST(slytd.NoOfArticlesSold_lastYTD AS DECIMAL) END AS NoOfArticlesSold_lastYTD
, CASE WHEN t.NoOfCustomers_lastYTD = 0 THEN NULL ELSE t.NoOfCustomers_lastYTD END AS NoOfCustomers_lastYTD
FROM SalesInPeriod s
JOIN SalesYTD sytd ON sytd.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesInPeriodLastYear sl ON sl.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesLastYTD slytd ON slytd.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
JOIN Totals t ON 1=1
)

SELECT
 t.Lev1ArticleHierarchyName
, NULL AS total
, x.Data
, CASE WHEN x.periode = 0 THEN NULL ELSE x.periode END AS periode
, CASE WHEN x.ytd = 0 THEN NULL ELSE x.ytd END AS ytd
, CASE WHEN x.periode_lastYear = 0 THEN NULL ELSE x.periode_lastYear END AS periode_lastYear
, CASE WHEN x.ytd_lastYear = 0 THEN NULL ELSE x.ytd_lastYear END AS ytd_lastYear
FROM Total t
CROSS APPLY (
	VALUES
        ('1 Revenue' , t.Revenue, t.Revenue_YTD, t.Revenue_lastYear, t.Revenue_lastYTD),
        ('2 NoOfArticles' , t.NoOfArticlesSold, t.NoOfArticlesSold_YTD, t.NoOfArticlesSold_lastYear, t.NoOfArticlesSold_lastYTD),
        -- ('3 NoOfCustomers' , t.NoOfCustomers, t.NoOfCustomers_YTD, t.NoOfCustomers_lastYear, t.NoOfCustomers_lastYTD),
		('4 RevenuePerCustomer', (t.Revenue/t.NoOfCustomers) , (t.Revenue_YTD/t.NoOfCustomers_YTD), (t.Revenue_lastYear/t.NoOfCustomers_lastYear), (t.Revenue_lastYTD/t.NoOfCustomers_lastYTD)),
		('5 ItemsPerCustomer', (t.NoOfArticlesSold/t.NoOfCustomers),(t.NoOfArticlesSold_YTD/t.NoOfCustomers_YTD),(t.NoOfArticlesSold_lastYear/t.NoOfCustomers_lastYear),(t.NoOfArticlesSold_lastYTD/t.NoOfCustomers_lastYTD)),
		('6 PricePerItem', (t.Revenue/t.NoOfArticlesSold), (t.Revenue_YTD/t.NoOfArticlesSold_YTD),(t.Revenue_lastYear/t.NoOfArticlesSold_lastYear),(t.Revenue_lastYTD/t.NoOfArticlesSold_lastYTD) )
  ) x (Data, periode, ytd, periode_lastYear, ytd_lastYear)
WHERE t.Revenue <> 0

   UNION 

	SELECT
	'Total' AS Lev1ArticleHierarchyName
	, 'Total' AS Total
	, x.Data
	, CASE WHEN x.periode = 0 THEN NULL ELSE x.periode END AS periode
	, CASE WHEN x.ytd = 0 THEN NULL ELSE x.ytd END AS ytd
	, CASE WHEN x.periode_lastYear = 0 THEN NULL ELSE x.periode_lastYear END AS periode_lastYear
	, CASE WHEN x.ytd_lastYear = 0 THEN NULL ELSE x.ytd_lastYear END AS ytd_lastYear
	FROM Totals t
	CROSS APPLY (
			VALUES
				('1 Revenue' , t.Revenue, t.Revenue_YTD, t.Revenue_lastYear, t.Revenue_lastYTD),
				('2 NoOfArticles' , t.NoOfArticlesSold, t.NoOfArticlesSold_YTD, t.NoOfArticlesSold_lastYear, t.NoOfArticlesSold_lastYTD),
			    ('3 NoOfCustomers' , t.NoOfCustomers, t.NoOfCustomers_YTD, t.NoOfCustomers_lastYear, t.NoOfCustomers_lastYTD),
				('4 RevenuePerCustomer', (t.Revenue/t.NoOfCustomers) , (t.Revenue_YTD/t.NoOfCustomers_YTD), (t.Revenue_lastYear/t.NoOfCustomers_lastYear), (t.Revenue_lastYTD/t.NoOfCustomers_lastYTD)),
				('5 ItemsPerCustomer', (t.NoOfArticlesSold/t.NoOfCustomers),(t.NoOfArticlesSold_YTD/t.NoOfCustomers_YTD),(t.NoOfArticlesSold_lastYear/t.NoOfCustomers_lastYear),(t.NoOfArticlesSold_lastYTD/t.NoOfCustomers_lastYTD)),
				('6 PricePerItem', (t.Revenue/t.NoOfArticlesSold), (t.Revenue_YTD/t.NoOfArticlesSold_YTD),(t.Revenue_lastYear/t.NoOfArticlesSold_lastYear),(t.Revenue_lastYTD/t.NoOfArticlesSold_lastYTD) )
	  ) x (Data, periode, ytd, periode_lastYear, ytd_lastYear)

ORDER BY data, Total, t.Lev1ArticleHierarchyName ASC


END -- 1 Pick And Collect

IF ( @WhichSales = 2 )		-- 2 all sales except Pick And Collect
BEGIN


----------------------------------------------------------------------
--Select
----------------------------------------------------------------------
;WITH flightReceipts AS (
	SELECT 
		FLOOR(receiptidx/1000) AS ReceiptHeadIdx,
		ds.StoreName, 
		se.ReceiptDateIdx, 
		CASE transtypevaluetxt4
						WHEN 'D' THEN transtypevaluetxt1 + ' - ' + se.TransTypeValueTxt3 
						WHEN 'A' THEN transtypevaluetxt1 + ' - ' + se.TransTypeValueTxt2	
						ELSE 	transtypevaluetxt1	
				END AS FlightNo,
			CASE 
					WHEN (transtypevaluetxt4 = 'D' OR transtypevaluetxt1 = 'AVN001') THEN 'Avgang' 
					WHEN (transtypevaluetxt4 = 'A' OR transtypevaluetxt1 = 'AVN000') THEN 'Ankomst'
					--WHEN '' THEN 'Ekstra'	
					ELSE 	''	
			END  AS FlightType
	FROM RBIM.Cov_customersalesevent se (NOLOCK)
	JOIN RBIM.Dim_TransType (NOLOCK) tt ON tt.TransTypeIdx = Se.TransTypeIdx
	JOIN RBIM.Dim_Date dd (NOLOCK) ON dd.dateidx = se.receiptdateidx
	JOIN @stores ds ON ds.storeidx = se.storeidx
	WHERE tt.transtypeId = 90403									
	AND (se.ReceiptDateIdx BETWEEN @DateFromIdx AND @DateToIdx
			OR se.ReceiptDateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear
			OR se.ReceiptDateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx
			OR se.ReceiptDateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear)
	AND (	@ReportType = 0 -- all flights
			OR (@ReportType = 1 AND (se.TransTypeValueTxt4 = 'D' OR se.TransTypeValueTxt1 = 'AVN001')) -- departure flights
			OR (@ReportType = 2 AND (se.TransTypeValueTxt4 = 'A' OR se.TransTypeValueTxt1 = 'AVN000')) -- arrival flights
			--OR (@ReportType = 3 AND se.TransTypeValueTxt4 = '') -- extra flights
	 )
	AND (	@AirportCodes IS NULL  --no filtering on airport codes
			OR (se.TransTypeValueTxt2  IN (SELECT AirportCode FROM @codes)) 
			OR (se.TransTypeValueTxt3  IN (SELECT AirportCode FROM @codes)) 
		 )
	AND (	@FlightNo IS NULL  --no filtering on flight no
			OR (se.TransTypeValueTxt1  IN (SELECT FlightNo FROM @flights)) 
		 )
),
SalesReceipts AS (
SELECT 
		FLOOR(f.ReceiptIdx/1000) AS ReceiptHeadIdx,
		f.ReceiptId,
		f.ReceiptDateIdx,
		da.ArticleId,
		da.ArticleName,
		da.Lev1ArticleHierarchyId,
		da.Lev1ArticleHierarchyName,
		(f.QuantityOfArticlesSold-f.QuantityOfArticlesInReturn) AS NoOfArticlesSold,
		(f.SalesAmountExclVat+f.ReturnAmountExclVat) AS Revenue,
		f.NumberOfCustomers AS NoOfCustomers
	FROM RBIM.Fact_ReceiptRowSalesAndReturn f (NOLOCK)
	JOIN RBIM.Dim_Article da (NOLOCK) ON da.ArticleIdx = f.ArticleIdx
	JOIN @stores ds  ON ds.storeidx = f.storeidx
	WHERE (f.ReceiptDateIdx BETWEEN @DateFromIdx AND @DateToIdx
			OR f.ReceiptDateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear
			OR f.ReceiptDateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx
			OR f.ReceiptDateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear)
	--AND (f.QuantityOfArticlesSold-f.QuantityOfArticlesInReturn) <> 0 
	--AND (f.SalesAmountExclVat+f.ReturnAmountExclVat) <> 0
), 

SalesInPeriod AS (
SELECT  
SALES.Lev1ArticleHierarchyName,
SUM(SALES.NoOfArticlesSold) AS NoOfArticlesSold,
SUM(SALES.Revenue) AS Revenue,
SUM(SALES.NoOfCustomers) AS NoOfCustomers
FROM  
(
	SELECT 
		ReceiptHeadIdx
	FROM flightReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdx AND @DateToIdx	
) FLIGHT
INNER JOIN 
(
	SELECT 
		ReceiptHeadIdx,
		ReceiptId,
		ArticleId,
		Lev1ArticleHierarchyName,
		NoOfArticlesSold,
		Revenue,
		NoOfCustomers
	FROM SalesReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdx AND @DateToIdx							
	
) SALES
ON FLIGHT.ReceiptHeadIdx = SALES.ReceiptHeadIdx 
WHERE --Filter on article selection
   (@ArticleSelection IS NULL OR SALES.ArticleID IN (SELECT ArticleId FROM @articles))
GROUP BY 
SALES.Lev1ArticleHierarchyName
--HAVING SUM(Revenue) <> 0
),

salesInPeriodLastYear AS (
SELECT  
SALES.Lev1ArticleHierarchyName,
SUM(SALES.NoOfArticlesSold) AS NoOfArticlesSold_lastYear,
SUM(SALES.Revenue) AS Revenue_lastYear,
SUM(SALES.NoOfCustomers) AS NoOfCustomers_lastYear
FROM  
(
	SELECT 
		ReceiptHeadIdx
	FROM flightReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear
) FLIGHT
INNER JOIN 
(
	SELECT 
		ReceiptHeadIdx,
		ReceiptId,
		ArticleId,
		Lev1ArticleHierarchyName,
		NoOfArticlesSold,
		Revenue,
		NoOfCustomers
	FROM SalesReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear						
	
) SALES
ON FLIGHT.ReceiptHeadIdx = SALES.ReceiptHeadIdx 
WHERE --Filter on article selection
   (@ArticleSelection IS NULL OR SALES.ArticleID IN (SELECT ArticleId FROM @articles))
GROUP BY 
SALES.Lev1ArticleHierarchyName
--HAVING SUM(Revenue) <> 0
) 
, salesYtd AS (
SELECT  
SALES.Lev1ArticleHierarchyName,
SUM(SALES.NoOfArticlesSold) AS NoOfArticlesSold_ytd,
SUM(SALES.Revenue) AS Revenue_ytd,
SUM(SALES.NoOfCustomers) AS NoOfCustomers_ytd
FROM  
(
	SELECT 
		ReceiptHeadIdx
	FROM flightReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx
) FLIGHT
INNER JOIN 
(
	SELECT 
		ReceiptHeadIdx,
		ReceiptId,
		ArticleId,
		Lev1ArticleHierarchyName,
		NoOfArticlesSold,
		Revenue,
		NoOfCustomers
	FROM SalesReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx						
	
) SALES
ON FLIGHT.ReceiptHeadIdx = SALES.ReceiptHeadIdx 
WHERE --Filter on article selection
   (@ArticleSelection IS NULL OR SALES.ArticleID IN (SELECT ArticleId FROM @articles))
GROUP BY 
SALES.Lev1ArticleHierarchyName
--HAVING SUM(Revenue) <> 0
)
, SalesLastYTD AS (
SELECT  
SALES.Lev1ArticleHierarchyName,
SUM(SALES.NoOfArticlesSold) AS NoOfArticlesSold_lastYTD,
SUM(SALES.Revenue) AS Revenue_lastYTD,
SUM(SALES.NoOfCustomers) AS NoOfCustomers_lastYTD
FROM  
(
	SELECT 
		ReceiptHeadIdx
	FROM flightReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear
) FLIGHT
INNER JOIN 
(
	SELECT 
		ReceiptHeadIdx,
		ReceiptId,
		ArticleId,
		Lev1ArticleHierarchyName,
		NoOfArticlesSold,
		Revenue,
		NoOfCustomers
	FROM SalesReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear						
	
) SALES
ON FLIGHT.ReceiptHeadIdx = SALES.ReceiptHeadIdx 
WHERE --Filter on article selection
   (@ArticleSelection IS NULL OR SALES.ArticleID IN (SELECT ArticleId FROM @articles))
GROUP BY 
SALES.Lev1ArticleHierarchyName
--HAVING SUM(Revenue) <> 0
)


--PC Salg Start
,FlightPC AS (
	SELECT 
		APACO.orderID AS ReceiptHeadIdx, --FLOOR(f.ReceiptIdx/1000) AS ReceiptHeadIdx,
		APACO.orderID AS ReceiptId,--f.ReceiptId,
		dd.DateIdx    AS ReceiptDateIdx
	FROM CBIM.Agg_PickAndCollectOrders AS APACO (nolock) --P&C
	--INNER JOIN CBIM.Agg_PickAndCollectOrderLines AS APACOL (nolock) ON APACOL.OrderID = APACO.OrderID
	--inner join RBIM.Dim_Gtin dg (nolock)							ON dg.Gtin = APACOL.ArticleEan and dg.StatusId=1	--1=Aktiv,9=Slettet ...
	--inner join RBIM.Cov_ArticleGtin ag (nolock)						ON ag.GtinIdx = dg.GtinIdx
	--inner join RBIM.Dim_Article da (nolock)							ON da.ArticleIdx = ag.ArticleIdx and da.isCurrent=1
	INNER JOIN RBIM.Dim_Date AS DD ON (convert(date,APACO.PaymentSuccessTimeStamp,103)) = dd.FullDate
	JOIN @stores ds  ON ds.StoreId = APACO.StoreId
	WHERE (dd.DateIdx BETWEEN @DateFromIdx AND @DateToIdx
			OR dd.DateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear
			OR dd.DateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx
			OR dd.DateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear)
)

,SalesPC AS (
SELECT 
		APACO.orderID AS ReceiptHeadIdx,	--FLOOR(f.ReceiptIdx/1000) AS ReceiptHeadIdx,
		APACO.orderID AS ReceiptId,			--f.ReceiptId,
		dd.DateIdx    AS ReceiptDateIdx,
		da.ArticleId,
		da.ArticleName,
		da.Lev1ArticleHierarchyId,
		da.Lev1ArticleHierarchyName,
		APACOL.ReceivedQty AS NoOfArticlesSold,
		APACOL.ArticleDeliveredPrice AS Revenue,
		NoOfCustomers = (
				SELECT COUNT(*) FROM CBIM.Agg_PickAndCollectOrders AS APACO (nolock) --P&C
				--INNER JOIN CBIM.Agg_PickAndCollectOrderLines AS APACOL (nolock) ON APACOL.OrderID = APACO.OrderID
				INNER JOIN RBIM.Dim_Date AS DD ON (convert(date,APACO.PaymentSuccessTimeStamp,103)) = dd.FullDate
				JOIN @stores ds  ON ds.StoreId = APACO.StoreId
				WHERE (dd.DateIdx BETWEEN @DateFromIdx AND @DateToIdx
					OR dd.DateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear
					OR dd.DateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx
					OR dd.DateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear)
				)
	FROM CBIM.Agg_PickAndCollectOrders AS APACO (nolock) --P&C
	INNER JOIN CBIM.Agg_PickAndCollectOrderLines AS APACOL (nolock) ON APACOL.OrderID = APACO.OrderID
	inner join RBIM.Dim_Gtin dg (nolock)							ON dg.Gtin = APACOL.ArticleEan and dg.StatusId=1	--1=Aktiv,9=Slettet ...
	inner join RBIM.Cov_ArticleGtin ag (nolock)						ON ag.GtinIdx = dg.GtinIdx
	inner join RBIM.Dim_Article da (nolock)							ON da.ArticleIdx = ag.ArticleIdx and da.isCurrent=1
	INNER JOIN RBIM.Dim_Date AS DD ON (convert(date,APACO.PaymentSuccessTimeStamp,103)) = dd.FullDate
	JOIN @stores ds  ON ds.StoreId = APACO.StoreId
	WHERE (dd.DateIdx BETWEEN @DateFromIdx AND @DateToIdx
			OR dd.DateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear
			OR dd.DateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx
			OR dd.DateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear)
)

,SalesInPeriodPC AS (
SELECT  
SALES.Lev1ArticleHierarchyName,
SUM(SALES.NoOfArticlesSold) AS NoOfArticlesSold,
SUM(SALES.Revenue) AS Revenue,
MAX(SALES.NoOfCustomers) AS NoOfCustomers
FROM  
(
	SELECT 
		ReceiptHeadIdx
	FROM FlightPC--flightReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdx AND @DateToIdx	
) FLIGHT
INNER JOIN 
(
	SELECT 
		ReceiptHeadIdx,
		ReceiptId,
		ArticleId,
		Lev1ArticleHierarchyName,
		NoOfArticlesSold,
		Revenue,
		NoOfCustomers
	FROM SalesPC--SalesReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdx AND @DateToIdx							
	
) SALES
ON FLIGHT.ReceiptHeadIdx = SALES.ReceiptHeadIdx 
WHERE --Filter on article selection
   (@ArticleSelection IS NULL OR SALES.ArticleID IN (SELECT ArticleId FROM @articles))
GROUP BY 
SALES.Lev1ArticleHierarchyName
--HAVING SUM(Revenue) <> 0
)

,salesInPeriodLastYearPC AS (
SELECT  
SALES.Lev1ArticleHierarchyName,
SUM(SALES.NoOfArticlesSold) AS NoOfArticlesSold_lastYear,
SUM(SALES.Revenue) AS Revenue_lastYear,
MAX(SALES.NoOfCustomers) AS NoOfCustomers_lastYear
FROM  
(
	SELECT 
		ReceiptHeadIdx
	FROM FlightPC--flightReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear
) FLIGHT
INNER JOIN 
(
	SELECT 
		ReceiptHeadIdx,
		ReceiptId,
		ArticleId,
		Lev1ArticleHierarchyName,
		NoOfArticlesSold,
		Revenue,
		NoOfCustomers
	FROM SalesPC--SalesReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxLastYear AND @DateToIdxLastYear						
	
) SALES
ON FLIGHT.ReceiptHeadIdx = SALES.ReceiptHeadIdx 
WHERE --Filter on article selection
   (@ArticleSelection IS NULL OR SALES.ArticleID IN (SELECT ArticleId FROM @articles))
GROUP BY 
SALES.Lev1ArticleHierarchyName
--HAVING SUM(Revenue) <> 0
) 

,salesYtdPC AS (
SELECT  
SALES.Lev1ArticleHierarchyName,
SUM(SALES.NoOfArticlesSold) AS NoOfArticlesSold_ytd,
SUM(SALES.Revenue) AS Revenue_ytd,
MAX(SALES.NoOfCustomers) AS NoOfCustomers_ytd
FROM  
(
	SELECT 
		ReceiptHeadIdx
	FROM FlightPC--flightReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx
) FLIGHT
INNER JOIN 
(
	SELECT 
		ReceiptHeadIdx,
		ReceiptId,
		ArticleId,
		Lev1ArticleHierarchyName,
		NoOfArticlesSold,
		Revenue,
		NoOfCustomers
	FROM SalesPC--SalesReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxStartThisYear AND @DateToIdx						
	
) SALES
ON FLIGHT.ReceiptHeadIdx = SALES.ReceiptHeadIdx 
WHERE --Filter on article selection
   (@ArticleSelection IS NULL OR SALES.ArticleID IN (SELECT ArticleId FROM @articles))
GROUP BY 
SALES.Lev1ArticleHierarchyName
--HAVING SUM(Revenue) <> 0
), 

SalesLastYTDPC AS (
SELECT  
SALES.Lev1ArticleHierarchyName,
SUM(SALES.NoOfArticlesSold) AS NoOfArticlesSold_lastYTD,
SUM(SALES.Revenue) AS Revenue_lastYTD,
MAX(SALES.NoOfCustomers) AS NoOfCustomers_lastYTD
FROM  
(
	SELECT 
		ReceiptHeadIdx
	FROM FlightPC--flightReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear
) FLIGHT
INNER JOIN 
(
	SELECT 
		ReceiptHeadIdx,
		ReceiptId,
		ArticleId,
		Lev1ArticleHierarchyName,
		NoOfArticlesSold,
		Revenue,
		NoOfCustomers
	FROM SalesPC--SalesReceipts
	WHERE ReceiptDateIdx BETWEEN @DateFromIdxStartLastYear AND @DateToIdxLastYear						
	
) SALES
ON FLIGHT.ReceiptHeadIdx = SALES.ReceiptHeadIdx 
WHERE --Filter on article selection
   (@ArticleSelection IS NULL OR SALES.ArticleID IN (SELECT ArticleId FROM @articles))
GROUP BY 
SALES.Lev1ArticleHierarchyName
)

,Totals AS (
SELECT 
NULL AS Lev1ArticleHierarchyName
, SUM(s.NoOfCustomers) - MAX(sPC.NoOfCustomers) AS NoOfCustomers 
, SUM(sytd.NoOfCustomers_YTD) - MAX(sytdPC.NoOfCustomers_YTD) AS NoOfCustomers_YTD
, SUM(sl.NoOfCustomers_lastYear) - MAX(slPC.NoOfCustomers_lastYear) AS NoOfCustomers_lastYear
, SUM(slytd.NoOfCustomers_lastYTD) - MAX(slytdPC.NoOfCustomers_lastYTD)AS NoOfCustomers_lastYTD
, SUM(s.Revenue) - SUM(sPC.Revenue) AS Revenue
, SUM(sytd.Revenue_YTD) - SUM(sytdPC.Revenue_YTD) AS Revenue_YTD
, SUM(sl.Revenue_lastYear) - SUM(slPC.Revenue_lastYear) AS Revenue_lastYear
, SUM(slytd.Revenue_lastYTD) - SUM(slytdPC.Revenue_lastYTD) AS Revenue_lastYTD
, CAST(SUM(s.NoOfArticlesSold) - SUM(sPC.NoOfArticlesSold) AS DECIMAL) AS NoOfArticlesSold
, CAST(SUM(sytd.NoOfArticlesSold_YTD) - SUM(sytdPC.NoOfArticlesSold_YTD) AS DECIMAL) AS NoOfArticlesSold_YTD
, CAST(SUM(sl.NoOfArticlesSold_lastYear) - SUM(slPC.NoOfArticlesSold_lastYear) AS DECIMAL) AS NoOfArticlesSold_lastYear
, CAST(SUM(slytd.NoOfArticlesSold_lastYTD) - SUM(slytdPC.NoOfArticlesSold_lastYTD) AS DECIMAL) AS NoOfArticlesSold_lastYTD
FROM SalesInPeriod s
JOIN SalesYTD sytd ON sytd.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesInPeriodLastYear sl ON sl.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesLastYTD slytd ON slytd.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesInPeriodPC sPC ON sPC.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesYtdPC sytdPC ON sytdPC.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesInPeriodLastYearPC slPC ON slPC.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName  
LEFT JOIN SalesLastYTDPC slytdPC ON slytdPC.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
), 
Total AS (
SELECT s.Lev1ArticleHierarchyName
, s.Revenue
, CAST(s.NoOfArticlesSold-sPC.NoOfArticlesSold AS DECIMAL) AS NoOfArticlesSold
, (SELECT NoOfCustomers FROM Totals)  AS NoOfCustomers
, sytd.Revenue_YTD-sytdPC.Revenue_YTD AS Revenue_YTD
, CASE WHEN sytd.NoOfArticlesSold_YTD = 0 THEN NULL ELSE CAST(sytd.NoOfArticlesSold_YTD-sytdPC.NoOfArticlesSold_YTD AS DECIMAL) END AS NoOfArticlesSold_YTD
, CASE WHEN t.NoOfCustomers_YTD = 0 THEN NULL ELSE t.NoOfCustomers_YTD END AS NoOfCustomers_YTD
, sl.Revenue_lastYear-slPC.Revenue_lastYear AS Revenue_lastYear
, CASE WHEN sl.NoOfArticlesSold_lastYear = 0 THEN NULL ELSE CAST(sl.NoOfArticlesSold_lastYear-slPC.NoOfArticlesSold_lastYear AS DECIMAL) END AS NoOfArticlesSold_lastYear
, CASE WHEN t.NoOfCustomers_lastYear = 0 THEN NULL ELSE t.NoOfCustomers_lastYear END AS NoOfCustomers_lastYear
, slytd.Revenue_lastYTD-slytdPC.Revenue_lastYTD AS Revenue_lastYTD
, CASE WHEN slytd.NoOfArticlesSold_lastYTD = 0 THEN NULL ELSE CAST(slytd.NoOfArticlesSold_lastYTD-slytd.NoOfArticlesSold_lastYTD AS DECIMAL) END AS NoOfArticlesSold_lastYTD
, CASE WHEN t.NoOfCustomers_lastYTD = 0 THEN NULL ELSE t.NoOfCustomers_lastYTD END AS NoOfCustomers_lastYTD
FROM SalesInPeriod s
JOIN SalesYTD sytd ON sytd.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesInPeriodLastYear sl ON sl.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesLastYTD slytd ON slytd.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesInPeriodPC sPC ON sPC.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesYtdPC sytdPC ON sytdPC.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
LEFT JOIN SalesInPeriodLastYearPC slPC ON slPC.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName  
LEFT JOIN SalesLastYTDPC slytdPC ON slytdPC.Lev1ArticleHierarchyName = s.Lev1ArticleHierarchyName
JOIN Totals t ON 1=1
)
-- PC Salg slutt

--SELECT * FROM SalesPC
--SELECT * FROM Total

SELECT
	 t.Lev1ArticleHierarchyName
	, NULL AS total
	, x.Data
	, CASE WHEN x.periode = 0 THEN NULL ELSE x.periode END AS periode
	, CASE WHEN x.ytd = 0 THEN NULL ELSE x.ytd END AS ytd
	, CASE WHEN x.periode_lastYear = 0 THEN NULL ELSE x.periode_lastYear END AS periode_lastYear
	, CASE WHEN x.ytd_lastYear = 0 THEN NULL ELSE x.ytd_lastYear END AS ytd_lastYear
FROM Total t
CROSS APPLY (
	VALUES
        ('1 Revenue' , t.Revenue, t.Revenue_YTD, t.Revenue_lastYear, t.Revenue_lastYTD),
        ('2 NoOfArticles' , t.NoOfArticlesSold, t.NoOfArticlesSold_YTD, t.NoOfArticlesSold_lastYear, t.NoOfArticlesSold_lastYTD),
        -- ('3 NoOfCustomers' , t.NoOfCustomers, t.NoOfCustomers_YTD, t.NoOfCustomers_lastYear, t.NoOfCustomers_lastYTD),
		('4 RevenuePerCustomer', (t.Revenue/t.NoOfCustomers) , (t.Revenue_YTD/t.NoOfCustomers_YTD), (t.Revenue_lastYear/t.NoOfCustomers_lastYear), (t.Revenue_lastYTD/t.NoOfCustomers_lastYTD)),
		('5 ItemsPerCustomer', (t.NoOfArticlesSold/t.NoOfCustomers),(t.NoOfArticlesSold_YTD/t.NoOfCustomers_YTD),(t.NoOfArticlesSold_lastYear/t.NoOfCustomers_lastYear),(t.NoOfArticlesSold_lastYTD/t.NoOfCustomers_lastYTD)),
		('6 PricePerItem', (t.Revenue/t.NoOfArticlesSold), (t.Revenue_YTD/t.NoOfArticlesSold_YTD),(t.Revenue_lastYear/t.NoOfArticlesSold_lastYear),(t.Revenue_lastYTD/t.NoOfArticlesSold_lastYTD) )
  ) x (Data, periode, ytd, periode_lastYear, ytd_lastYear)
WHERE t.Revenue <> 0

UNION 

SELECT
	'Total' AS Lev1ArticleHierarchyName
	, 'Total' AS Total
	, x.Data
	, CASE WHEN x.periode = 0 THEN NULL ELSE x.periode END AS periode
	, CASE WHEN x.ytd = 0 THEN NULL ELSE x.ytd END AS ytd
	, CASE WHEN x.periode_lastYear = 0 THEN NULL ELSE x.periode_lastYear END AS periode_lastYear
	, CASE WHEN x.ytd_lastYear = 0 THEN NULL ELSE x.ytd_lastYear END AS ytd_lastYear
FROM Totals t
CROSS APPLY (
		VALUES
				('1 Revenue' , t.Revenue, t.Revenue_YTD, t.Revenue_lastYear, t.Revenue_lastYTD),
				('2 NoOfArticles' , t.NoOfArticlesSold, t.NoOfArticlesSold_YTD, t.NoOfArticlesSold_lastYear, t.NoOfArticlesSold_lastYTD),
			    ('3 NoOfCustomers' , t.NoOfCustomers, t.NoOfCustomers_YTD, t.NoOfCustomers_lastYear, t.NoOfCustomers_lastYTD),
				('4 RevenuePerCustomer', (t.Revenue/t.NoOfCustomers) , (t.Revenue_YTD/t.NoOfCustomers_YTD), (t.Revenue_lastYear/t.NoOfCustomers_lastYear), (t.Revenue_lastYTD/t.NoOfCustomers_lastYTD)),
				('5 ItemsPerCustomer', (t.NoOfArticlesSold/t.NoOfCustomers),(t.NoOfArticlesSold_YTD/t.NoOfCustomers_YTD),(t.NoOfArticlesSold_lastYear/t.NoOfCustomers_lastYear),(t.NoOfArticlesSold_lastYTD/t.NoOfCustomers_lastYTD)),
				('6 PricePerItem', (t.Revenue/t.NoOfArticlesSold), (t.Revenue_YTD/t.NoOfArticlesSold_YTD),(t.Revenue_lastYear/t.NoOfArticlesSold_lastYear),(t.Revenue_lastYTD/t.NoOfArticlesSold_lastYTD) )
	  ) x (Data, periode, ytd, periode_lastYear, ytd_lastYear)

ORDER BY data, Total, t.Lev1ArticleHierarchyName ASC




END -- 2 all sales except Pick And Collect

END -- Siste END



GO

