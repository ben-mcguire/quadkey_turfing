**Summary**: Teams in the public and non-profit sectors that want to conduct in-person outreach frequently lack the resources, time, and training to generate walking turf at scale. Automating turf production through the use of quadkeys (an open-source mapping method that translates address latitude-longitude into a global grid of ‘tiles’) offers a workable solution that is cheap, fast, and accessible to teams with limited resources; this paper shares process and code for how to operationalize these automated turf squares. (Note: This readme is also published on [Medium](https://medium.com/p/ef96a934e983))

## Introduction
Building effective programs in the public sector and non-profit spaces frequently demands that we reach people directly and in-person. And whether teams are going door-to-door to deliver resources or services, asking for signatures, sharing information, or convincing people to vote, the organization of that outreach requires that those who we would reach are split into separate turfs — proximate groups that let us structure the time of staff or volunteers effectively and efficiently.

In well-resourced environments and with lots of lead time, programs might want to use specialized tools to create bespoke turfs; political campaigns frequently train staff to build turf shapes in tools like VAN for Get Out The Vote efforts. And for government agencies and nonprofits conducting outreach in a long-term program, route planning tools from other sectors like ArcGIS are a great way to structure efforts. Where teams can run into challenges are in finding the staff and training time for hand-turfing tools, and in getting contracts for new software through thorny procurement processes.

When a team is struggling to acquire or use standalone tools quickly, there aren’t a lot of great options that don’t come with clear disadvantages or require advanced analytics skillsets. Simply splitting teams by political and functional geographies (e.g., precincts, districts, zip codes, Census blocks) is almost never a good solution because the density of the people we are trying to reach is not well-mapped to these areas — meaning that we will have some extremely dense areas and others that are extremely sparse. The features of an ideal solution would be to have something which adjusts to where people actually are, and let teams generate appropriately-sized turfs without needing to access expensive and time-consuming technology tools. During the 2020 presidential primary campaign of Democratic Senator Elizabeth Warren, the analytics team struck on one potential answer: Quadkeys.

## Introducing Quadkeys
Quadkeys are a tool created at Microsoft as a part of the Bing Tile Maps System, and are essentially a way to translate grid coordinates into tiles. Quoting directly from Microsoft’s public [documentation](https://docs.microsoft.com/en-us/bingmaps/articles/bing-maps-tile-system):

> Quadkeys have several interesting properties. First, the length of a quadkey (the number of digits) equals the level of detail of the corresponding tile. Second, the quadkey of any tile starts with the quadkey of its parent tile (the containing tile at the previous level). As shown in the example below, tile 2 is the parent of tiles 20 through 23, and tile 13 is the parent of tiles 130 through 133:

Put another way, adding one more character splits the Earth-sized ‘tile’ projection into four quadrants, all of which have the same characters as the parent tile, plus one additional character that can be 0 (at top left), 1 (top right), 2 (bottom left), or 3 (bottom right).

![image](https://github.com/user-attachments/assets/1338694c-95b0-4064-9e09-1b8ab8b75032)

Quadkeys are a translation of grid coordinates into tiles designated by a string in base 4, with each zoom level adding one new character, and each new character splitting the ‘parent’ tile into quadrants.
Quadkeys and tile maps are important for how Microsoft and Bing store and transmit mapping data; for our purposes, they have some critical properties:

- Size flexibility: It is easy to count how many addresses or locations are inside a quadkey tile at each level, and decide how large we want them to be to account for the density of underlying data, instead of the arbitrary lines that we would get by using political or functional geographies (e.g., zip codes).
- Accessibility for restructuring: Quadkeys can be manipulated and configured using only simple string manipulation; it is not necessary to procure or use any specialized software or tools to adjust quadkey size, just the ability to trim or add characters to the end of a string. We don’t need to use shape files or run complex geographic calculations, meaning that the engineering and expertise needed to go from targets to turf is accessible to many more data teams.
- Parent-child connections: Deciding how big we want to make the turf for any given set of addresses just requires counting how many addresses fall within each child of a parent quadkey, and then establishing a decision rule that assigns either parent or child length to that address, by keeping the length of the child quadkey or trimming one character to ‘zoom out’ to parent level.

### Case Study: Open Data on NYC Restaurants to Turfs
As an example of how quadkeys can be used to generate flexible and automated turfs cheaply and quickly, we will use open data on New York City restaurant inspections. To this data, we just need to append a quadkey based on the latitude-longitude of each restaurant; Microsoft makes code functions for this purpose publicly available.

If we imagined that we wanted to send out canvassers to restaurants to ask them to put a sign for our candidate in their front window, we might decide that we want some arbitrary number of restaurants per turf — for the purpose of this visual, 10–20 addresses might be our target density.



At zoom level 8 — that is, a quadkey that is 8 characters long — we have a single square that covers all of New York City. Adding one more character and cutting each square into four quadrants cuts to something turf-sized as we reach 15 to 18 characters, but we can also see that at that length, we have started to create lots of scattered turfs that are too small for our desired program. To simplify the problem, we can think about a set of locations in a single grid square and what we would get if we ‘zoomed’ in by having the quadkeys be one and then two characters longer.

![image](https://github.com/user-attachments/assets/3d79acf9-01d0-48e2-b885-b0d790462feb)

*Quadkeys at each subsequent zoom level split the parent tile into four ‘children’*

Now is the moment at which the parent-child connection between quadkey levels can be used to our advantage. All we need to do to establish a size-flexibility rule is group by quadkeys of different length, count addresses that fall within each child quadkey for that parent, and then set an arbitrary condition set for how many targets we want to have in each box. In other words, just by knowing how to count distinct targets and set up a case statement in a language like SQL, we can generate flexible turfs that have any density conditions we want, at any scale. Example code that achieves this balancing follows below:

![image](https://github.com/user-attachments/assets/5e6140f7-2dfb-4b7e-987e-aac2435409c4)

*Rather than use a GUI, specialized tool, or advanced geographic functions to make turf size flexible to density, all we need to do is be able to run a GROUP BY, COUNT, and simple CASE WHEN statement — all well within the ability of an analyst with rudimentary SQL knowledge.*

What this code does in practice is start by looking at the smallest box level, count how many addresses are in each child quadkey at that level, and then checks if that number is larger or smaller than an arbitrary condition that can be set in code. In the example below, we might decide that we want no more than six addresses in the smallest box — the counting operation will then instruct the code to assign the child level to all targets within that parent, and assign the parent level to boxes where that condition is not met.

![image](https://github.com/user-attachments/assets/8ebb0774-855a-42e3-9f24-41bd4557f6ae)

*The top left ‘parent’ box finds that one of the children meets the density condition we set, so all addresses in that parent box are assigned a quadkey at the child length. All addresses in parent boxes where that condition is not met are assigned the parent quadkey length.*

Just by counting addresses and appending or removing one character in a string, we have now created rudimentary turf that is responsive to how many addresses are in an area. But one challenge in the box above is that we’ve also created some very small turfs — the blue addresses that are not in the square that met the density condition.

For these turfs, we want to reconfigure again, and assign them directly to their best near neighbor. In this case, ‘near neighbor’ might mean looking for the closest address and arbitrarily linking these cut-off turfs to whichever address is nearby. There are other ways to accomplish this as well — for example, you could generate the centroid of addresses that are now grouped into turfs, and check for distance to that centroid. The specific nature of the technical solution is less important than the ability to reassign these turfs in a consistent, effective way. The code below offers one example of this decision rule process (which might work better for a smaller dataset) — setting up a cross join between addresses that meet certain conditions, and ranking by distance to find what is nearest.

![image](https://github.com/user-attachments/assets/dfcd0331-66af-484d-ac00-7c9e38165b43)

*This is just one simplified example of what finding a best near neighbor could look like; any operation that checks many potential matches can quickly become quite expensive, so any conditions or methods that reduce costs (e.g., turfs can not cross county lines, looking for the closest group of addresses instead of individual matches) are a good idea.*

What this code means in practice is that we look for turfs that are ‘too small’ relative to some condition we set, and reassign them to their closest neighbor that meet other conditions (e.g., are not part of a turf that is already ‘too big’).

![image](https://github.com/user-attachments/assets/29ce796a-859e-403a-8029-707cf4fa21fc)

*Some of the blue addresses join their fellows and become a larger blue turf; one other finds that the red turf is slightly closer and so joins it. The conditions here can be as simple or as complex as is needed for the program in question; rules defining ‘who’ the best near neighbor is should be designed for operational quality, not only technical definitions.*

For many larger operations, especially in the political space, cutting turf using traditional tools might be relatively easy because new institutional investments in tools and training needs could be minimal. But for smaller, newer teams with fewer resources, quadkeys mean that we can start with a set of addresses, generate density-adjusted turfs, and optimize for distance and size, with a vastly simplified technical toolkit.

![image](https://github.com/user-attachments/assets/0534dc41-333e-4829-89f5-177d0e4cf852)

*The technical knowledge required to achieve this transformation is only rudimentary SQL, far more accessible to smaller and less-well resourced teams that want to achieve outreach goals.*

With just a few lines of rudimentary SQL code, we have turned a list of 30,000 restaurants into organized, density-optimized turfs, which we can easily use to send out teams for outreach. All of the data that we used to generate the turfs below (in Williamsburg, Brooklyn) was publicly available, and the SQL used to reconfigure the quadkeys is no more than a few dozen lines long.

![image](https://github.com/user-attachments/assets/e1751090-5424-4323-8abc-ce401dbcdab6)

![image](https://github.com/user-attachments/assets/54c9b8a4-be79-4d2c-8308-270c2671f6a6)

*Generating density-optimized turfs for our theoretical restaurant window sign program just required that we append a quadkey string to publicly available locations data and reconfigure for density using simple SQL code.*

## Turf Maintenance and Re-Turfing
One of the other exciting consequences of using quadkeys and automatic density adjustment rather than manual turfing is that turf maintenance and ‘returfing’ — that is, adjusting to a program need to remove addresses for some reason or add new addresses into the mix — just requires re-running the same code that generated the original turfs. The same decision rules that generated initial density conditions will ingest new data that says where density has changed, and adjust the size of turfs accordingly.

![image](https://github.com/user-attachments/assets/0881b1fd-85a6-4921-bdfe-62f46cdaa8fc)

In other words, assigning turfs and making the shape of outreach work reflect program results can be as simple as just running the same query that was used to generate initial turfs. In real terms, what that means is that teams can spend less time on the logistics of data and mapping, and the program can spend more time on the reaching human beings.

## Using Quadkeys for Turf in the Real World
In the Warren campaign, quadkeys were used to prioritize high-density locations from which to launch ‘distributed canvass’ teams. Turfs were generated by the analytics team and distributed by organizers to volunteers, who would pull a list of the nearest 40 doors in a specialized mobile phone tool at the center point of quadkeys that were ranked by the density of target voters. Using quadkey decision rules to sort turf via decision rule let the campaign knock millions of doors across the country without spending limited resources on the turf mapping process. It is important to emphasize, however, that the operational and organizing leadership required to run a program at that scale was far more important than the technical solution: quadkeys were a way to streamline data process and prioritization, but they did not create the underlying program in any form. Ben McGuire and Mick Thompson partnered under the leadership of Kass DeVorsey with help from a great analytics team to generate the original quadkey turf work on the Warren campaign. But it is the organizing teams and especially those working on the ground in states, led by Kunoor Ojha and others, who deserve 100% of the credit for turning this technical tool into a voter-contact program at phenomenal scale.

In subsequent outreach work in New York City related to COVID-19 vaccination mandates, quadkeys were used to generate Citywide turf for business outreach. Rather than spend precious days hand-cutting data into turfs or trying to navigate a multi-agency procurement process for a dedicated turfing tool, quadkeys and SQL were used to create turf for the entire City in a matter of minutes. This meant that instead of getting bogged down in the data and manual labor of cutting turfs, the operational team could immediately focus their attention and energy on the conversations happening on the doorstep.

There will likely always be contact operations where hand-cut turf and specialized tools are the right answer — because of program timing, density, geography, and what partners or volunteers can do. But the more time we spend cutting and auditing turf, the less time we can spend doing the things that matter: talking to people and building relationships.

When program teams need to move fast and the overall address density is lower or extremely varied (e.g., business outreach, form follow-up, ballot chase, ballot cure, longer-term relational contacts), having a perfectly cut turf may not be worth the investment of time to build and maintain over the course of a campaign. In those cases, automatically building turfs using quadkeys presents a useful, cheap, and accessible alternative that can be used wherever geocoded address data is available using simple SQL code.

