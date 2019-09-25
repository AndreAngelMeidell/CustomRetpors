USE [VBDCM]
GO

/****** Object:  StoredProcedure [dbo].[usp_CBI_ds1375StockCountArticleDetail_report]    Script Date: 19.09.2019 08:58:53 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




create procedure [dbo].[usp_CBI_ds1375StockCountArticleDetail_report]
(
	@StoreId			varchar(50)
	,@StockCountNo		int
	,@DeviationOnly		bit	= 0
)
as
begin
	set nocount on 
	
	select
		ss.EANNo
		,ss.ArticleName
		,ss.ArticleGroup
		,ss.InStockQty
		,ss.CountedQty
		,ss.DeviationQty
		,ss.PriorCountNetCostAmount
		,ss.CountedNetCostAmount
		,case when (ss.DeviationQty <> 0) then
			isnull(ss.CountedNetCostAmount,0) - isnull(ss.PriorCountNetCostAmount,0)
		else
			0.00
		end			'DeviationCostAmount'
	from
		(
		select 
			art.EANNo																												'EANNo'
			,art.ArticleName																										'ArticleName'
			,concat(isnull(cast(art.ArticleHierNo as varchar(max)),''),'-',isnull(art.ArticleHierName,''))							'ArticleGroup'
			,sscl.InStockQty																										'InStockQty'
			,sscl.CountedQty																										'CountedQty'
			,isnull(sscl.CountedQty,0) - isnull(sscl.InStockQty,0)																	'DeviationQty'
			,isnull(sscl.CountedDerivedNetCostAmount,sscl.CountedNetCostAmount)														'CountedNetCostAmount'
			,isnull(sscl.InStockQty,0) * coalesce(nullif(sscl.NetPriceDerivedClosedDate,0),sscl.NetPrice,sscl.NetPriceClosedDate)	'PriorCountNetCostAmount'
		from
			StoreStockCountLines sscl with (nolock)
		inner join Stores s  with (nolock) on sscl.StoreNo=s.StoreNo
		inner join AllArticles art  with (nolock) on art.ArticleNo=sscl.ArticleNo
		where
				sscl.stockcountno=@StockCountNo
			and s.Storeid=@StoreId
		) ss
	where
		(@DeviationOnly=0 or (@DeviationOnly=1 and DeviationQty <> 0))
	order by
		ArticleName
end



GO

