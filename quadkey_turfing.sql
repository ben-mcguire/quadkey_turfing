DROP TABLE IF EXISTS project.schema.my_quadkey_universe;
CREATE TABLE project.schema.my_quadkey_universe AS 
-- Geography for Cure Canvassing

    WITH base AS (
        SELECT id
            , CONCAT(person.first_name,CONCAT(" ",person.last_name)) name
            , state
            , city 
            , county 
            , zip 
            , address
            , address_latitude
            , address_longitude
            , quadkeys.quadkey 
        FROM base
        LEFT JOIN (
            SELECT id
                , LEFT(quadkey,/*Smallest quadkey (i.e., deepest zoom level) desired*/) quadkey
            FROM project.schema.person_quadkeys 
        ) quadkeys ON base.id = quadkeys.id
        WHERE /*Insert relevant universe restrictions here (e.g., scores, registration status, voting history, survey question*/
    
    -- For the purposes of this example code, we will imagine that we want to have quadkey length nine as our largest turf size,
    -- and quadkey 14 as the smallest possible. The useful level of granularity for your project depends on your own local universe
    -- and geographies; theoretically, there are no limits to how many discrete levels you want to include in your size flexibility.
    
    -- We start by checking the max value of each level 10 quadkey within every level 9 quadkey, and then move sequentially through
    -- each quadkey level, building out a separate listing for each level.
    
    , qk0910 AS (
        SELECT /*Whatever geography level is relevant as an organizing principle (e.g., county, state house district)*/ geo
            , LEFT(quadkey,9) AS big 
            , LEFT(quadkey,10) AS small
            , COUNT(DISTINCT id) ct
        FROM base
        GROUP BY 1,2,3)
    
    , qk1011 AS (
        SELECT geo 
            , LEFT(qk14,10) AS big 
            , LEFT(qk14,11) AS small
            , COUNT(DISTINCT id) ct
        FROM base
        GROUP BY 1,2,3)
    
    , qk1112 AS (
        SELECT geo 
            , LEFT(qk14,11) AS big 
            , LEFT(qk14,12) AS small
            , COUNT(DISTINCT id) ct
        FROM base
        GROUP BY 1,2,3)
    
    , qk1213 AS (
        SELECT geo 
            , LEFT(qk14,12) AS big 
            , LEFT(qk14,13) AS small
            , COUNT(DISTINCT id) ct
        FROM base
        GROUP BY 1,2,3)
    
    , qk1314 AS (
        SELECT geo 
            , LEFT(qk14,13) AS big 
            , LEFT(qk14,14) AS small
            , COUNT(DISTINCT id) ct
        FROM base
        GROUP BY 1,2,3)
    
    -- Now that we've identified the max level of targets at each sub-level per main level, all
    -- we need to do is say for each id, what is the value of each sublevel, joining on each id's
    -- actual quadkey to the CTEs above. We are able to do this because of quadkey's nesting feature;
    -- all we need to do is join on the left-trimmed versions of the id's quadkey to its relevant partner.
    
    , selection AS (
        SELECT base.id 
            , MAX(qk0910.ct) nineten
            , MAX(qk1011.ct) teneleven
            , MAX(qk1112.ct) eleventwelve
            , MAX(qk1213.ct) twelvethirteen
            , MAX(qk1314.ct) thirteenfourteen
        FROM base
        LEFT JOIN qk0910 ON left(base.qk14,9) = qk0910.big AND base.geo = qk0910.geo
        LEFT JOIN qk1011 ON left(base.qk14,10) = qk1011.big AND base.geo = qk1011.geo
        LEFT JOIN qk1112 ON left(base.qk14,11) = qk1112.big AND base.geo = qk1112.geo
        LEFT JOIN qk1213 ON left(base.qk14,12) = qk1213.big AND base.geo = qk1213.geo
        LEFT JOIN qk1314 ON left(base.qk14,13) = qk1314.big AND base.geo = qk1314.geo
        GROUP BY 1
    )

    -- With each id assigned a max value per sub-level, we can stand up size-flexible turf
    -- based on user-inputted parameters. The values of 'X' below can be set at any level;
    -- effectively, what you're doing is saying that if the value in my smallest/most-granular zoomed
    -- level exceeds a certain amount, then all ids in that main level will be grouped by the that 
    -- smallest level of turf, and so on and so on. 

    , size_selection AS (
        SELECT myv_van_id vanid
            , CASE WHEN thirteenfourteen >= X THEN '14'
                WHEN twelvethirteen >= X THEN '13'
                WHEN eleventwelve >= X THEN '12'
                WHEN teneleven >= X THEN '11'
                WHEN nineten >= X THEN '10'
                ELSE '09' END AS size 
        FROM selection
    )
    
    -- We now append our newly-defined quadkey by simply left-trimming in a case that runs through
    -- each size option, starting from the largest and going down to the smallest.
    
    SELECT *, 
        CASE WHEN size = '09' THEN LEFT(qk14,9)
            WHEN size = '10' THEN LEFT(qk14,10)
            WHEN size = '11' THEN LEFT(qk14,11)
            WHEN size = '12' THEN LEFT(qk14,12)
            WHEN size = '13' THEN LEFT(qk14,13)
            WHEN size = '14' THEN LEFT(qk14,14) 
        END AS quadkey_size_flexibility
    FROM base 
    LEFT JOIN size_selection ON base.id = size_selection.id

;
DROP TABLE IF EXISTS project.schema.alternative_quadkeys;
CREATE TABLE project.schema.alternative_quadkeys AS

-- Alternative Geography
    WITH infra AS (
        SELECT geo 
            , quadkey_size_flexibility 
            , COUNT(DISTINCT id) turf_count_one
            
            -- If we wanted to stop now that we have our size-flexible turfs defined, we can simply append a list number at the geo level and 
            -- move on. But I am building it here so that is available downstream for comparison with the alternative list number that will 
            -- come from distance optimization from small turfs.
            
            , CONCAT(geo,
                CONCAT(" - ",
                LPAD(CAST(ROW_NUMBER () OVER (PARTITION BY geo ORDER BY COUNT(DISTINCT id) DESC) AS STRING),2,'0'))) list_number
        FROM project.schema.my_quadkey_universe
        GROUP BY 1,2
    )
    
    -- To pick the best neighbor for each small turf, all we need to do is get the distance to relevant
    -- other points, and set a row numnber partition ranked by distance. Thanks to the geo functions now 
    -- available in a lot of SQL databases, this is straightforward - for databases without these functions
    -- built in, a bit of geometry gets you there quickly as well.
    
    , distance AS (
        SELECT primary, secondary_quadkey
        FROM (
            SELECT primary.id primary
                , secondary.id secondary
                , secondary.quadkey_size_flexibility secondary_quadkey
                , ROW_NUMBER() OVER (
                    PARTITION BY primary.id  
                    ORDER BY ST_Distance(
                        ST_GeogPoint(primary.address_longitude, primary.address_latitude)
                        , ST_GeogPoint(secondary.address_longitude, secondary.address_latitude)) ASC) AS dist_meters
            FROM (
                SELECT DISTINCT id
                  , address_longitude
                  , address_latitude
                  , base.geo
                  , base.quadkey_size_flexibility
                  , infra.turf_count_one
                FROM project.schema.my_quadkey_universe base
                LEFT JOIN infra 
                ON base.quadkey_size_flexibility = infra.quadkey_size_flexibility 
                  AND base.geo = infra.geo) primary
            CROSS JOIN (
                SELECT DISTINCT id
                  , address_longitude
                  , address_latitude
                  , base.geo
                  , base.quadkey_size_flexibility
                  , infra.turf_count_one
                FROM project.schema.my_quadkey_universe base
                LEFT JOIN infra 
                ON base.quadkey_size_flexibility = infra.quadkey_size_flexibility 
                  AND base.geo = infra.geo) secondary
            
            -- Cross joins are expensive, which means any conditions we can set here are useful in reducing unnecessary costs.
            -- Immediate examples might be rules about size (e.g., you only care about turfs that aren't too big or small, or
            -- you might not want turfs to cross things like county lines. While this example is crossing at the person level, 
            -- you can also partition over distance to nearby turfs (e.g., to the latitude-longitude centroid of nearby turfs 
            -- that already exist) which would dramatically reduce database costs. If you want, you can even add the initial turf
            -- count of the primary ids in the where clause (i.e., only look for nearest neighbor if the turfs are small enough
            -- for you to care). The right approach here just depends on how you want to do iteration and checking.
            
            WHERE primary.geo = secondary.geo
            AND primary.id != secondary.id
            AND secondary.turf_count_one >= /*Only reassign to turfs that exceed a certain size threshold (i.e., don't just combine very small turfs)*/
            AND secondary.turf_count_one <= /*Only reassign to turfs that aren't already too crowded (i.e., where adding more would make the turf unworkable)*/
        
        ) WHERE dist_meters = 1
    )
    
    -- Now, all you need to do is set a parameter for which turfs you want to re-assign. At whatever level you set,
    -- those IDs will be shifted to the quadkey of the person/turf that ids ranked first in closest distance.
    
    , conversion AS (
        SELECT id
            , geo
            , CASE WHEN infra.turf_count_one < /*Pick a level at which all ids in a turf will be reassigned to their closest neighbor*/
                THEN distance.secondary_quadkey
                ELSE cure_canvass_universe.quadkey_size_flexibility END AS alternative_quadkey
        FROM project.schema.my_quadkey_universe
        LEFT JOIN infra ON cure_canvass_universe.quadkey_size_flexibility = infra.quadkey_size_flexibility 
        AND cure_canvass_universe.geo = infra.geo
        LEFT JOIN distance ON cure_canvass_universe.id = distance.primary
    )
    
    SELECT base.id
        , base.state
        , base.city 
        , base.county 
        , base.zip 
        , base.address
        , base.address_latitude
        , base.address_longitude 
        , base.quadkey max_zoom_level_quadkey 
        , base.size 
        , base.quadkey_size_flexibility
        , infra.list_number 
        , conversion.alternative_quadkey 
    FROM project.schema.my_quadkey_universe base
    LEFT JOIN infra ON base.quadkey_size_flexibility = infra.quadkey_size_flexibility 
    AND base.geo = infra.geo
    LEFT JOIN conversion ON base.id = conversion.id 
    LEFT JOIN distance ON base.id = distance.primary

;
DROP TABLE IF EXISTS project.schema.alternative_list_number;
CREATE TABLE project.schema.alternative_list_number AS

-- Now, we can append a simple list number for our final turfs, roughly optimized for density and distance.
-- This example assumes list numbers denominated by some geographic level, but the nomenclature can be 
-- flexible to whatever you're using.

-- Shipping Query
    WITH alt_infra AS (
        SELECT geo
            , alternative_quadkey 
            , COUNT(DISTINCT id) turf_count_update
            , CONCAT(geo,
                CONCAT(" - ",LPAD(CAST(ROW_NUMBER () OVER (PARTITION BY geo ORDER BY COUNT(DISTINCT id) DESC) AS STRING),2,'0'))) alternative_list_number
        FROM project.schema.alternative_quadkeys 
        GROUP BY 1,2
    )

    SELECT * 
        , alt_infra.alternative_list_number
    FROM project.schema.alternative_quadkeys alt
    LEFT JOIN alt_infra ON alt.alternative_quadkey = alt_infra.alternative_quadkey 
    AND alt.geo = alt_infra.geo
    
;
