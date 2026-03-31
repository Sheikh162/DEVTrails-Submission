
# Vritti: A Safety Net for Delivery Riders

**Tagline:** Protecting the pockets of the people who feed our cities.

## 1. What is Vritti?

Vritti is a weekly income-protection plan built specifically for food delivery riders (Swiggy, Zomato, Uber Eats). While most insurance covers hospital bills or bike crashes, Vritti is different: it protects a rider's **daily earnings** when things outside their control , like severe floods, extreme heatwaves, or unexpected city strikes , stop them from working.

## The Problem

For a gig worker, three hours of extreme rain isn't just bad weather; it means losing a whole day's pay. Since most riders live week-to-week, just a few disrupted days can push them into debt.

## The Solution

A safety net that works automatically. Riders pay a tiny weekly fee. If a major disruption hits their city, our system instantly sends money straight to their bank account to cover what they would have earned. No claim forms, no customer care calls, no waiting.

---

## 2. How It Works (The Math Behind the Magic)

## The Premium Model (Weekly SIP Inflow)

The weekly premium ($P$) is dynamically calculated every Saturday. It uses the worker’s actual earning capacity (verified securely via the Account Aggregator) and their city's baseline weather risk to ensure the cost is always fair and affordable.

$$P=[B\times W_{loc}]\times(1-L)$$

- **Base Rate ($B$):** Determined by the worker's weekly earnings bracket.
    
    - Bracket 1 (₹1,000 – ₹5,000 earnings): **₹100**
        
    - Bracket 2 (₹5,000 – ₹10,000 earnings): **₹200**
        
    - Bracket 3 (₹10,000+ earnings): **₹300**
        
- **Location Weight ($W_{loc}$):** Adjusts for the baseline environmental risk of the city.
    
    - Urban Hubs (High Density/Pollution - e.g., Delhi, Chennai): **1.5**
        
    - Semi-Urban/Tier-2 Hubs: **1.0**
        
- **Loyalty Discount ($L$):** Rewards consistent, honest workers. Ranging from **0.0 to 0.3**. For every 4 weeks of consecutive active status on the platform, a **0.05 (5%)** discount is applied, capped at a maximum of **30%**.
    

## The Payout Model (Automated Relief Outflow)

When an official disruption occurs, the payout ($Y_{total}$) is triggered automatically. We do not measure individual "suffering"; we measure the **City's Disruption Level** and replace the lost opportunity to earn.

$$Y_{total}=(Y_{base}\times M_{severity})\times T_{pro\_rata}$$

- **Base Daily Payout ($Y_{base}$):** The median daily earnings for that specific city (e.g., **₹500**).
    
- **Severity Multiplier ($M_{severity}$):** Scales the payout based on the intensity of the event.
    
    - Orange Alert / Transport Strike: **1.0x** (Standard daily loss)
        
    - Red Alert / Severe Cyclone: **1.5x** (Accounts for hazard pay/extended recovery)
        
- **Time Factor ($T_{pro\_rata}$):** Calculated in 3-hour blocks. If Swiggy/Zomato officially suspends service for just 3 hours during a sudden extreme - rainfall , the payout is pro-rated (e.g., **0.3x** of the daily rate) to cover that specific lost window.
    

---

## 3. Security Analysis

> _What happens if 500 people sitting at home in Mumbai use fake GPS apps to pretend they are stuck in a Chennai flood just to steal the payout money?_

We built Vritti to be completely scam-proof without spying on our honest users. Instead of just trusting the phone's GPS (which is easy to fake), we look at the **physical environment** around the phone.

## Spotting a Fake vs A Real Rider

- **The Real Rider:** Their phone feels the sudden drop in air pressure from the storm, and it vibrates from the bike engine or footsteps.
    
- **The Scammer:** Their phone's GPS says they are moving, but the phone is actually sitting perfectly still on a desk indoors. Our AI catches this immediately.
    

## The "Invisible" Checks We Run

- **Cell Tower Check:** If someone claims to be in Chennai, but their phone is pinging a Mumbai cell tower, we block the claim.
    
- **Wi-Fi Neighborhood Check:** We look at the names of the Wi-Fi routers nearby. If the routers match a residential block in Delhi but the GPS says Chennai, we know it's a fake.
    
- **The "Actually Working" Check:** We securely check their past 7 days of Swiggy/Zomato payouts. If they haven't been actively delivering, they don't get the disaster payout.
    

---

## 4. The Backend abstraction

We split our technology into two parts to keep it fast, private, and smart.

## Part 1: The App on the Phone 

We don't want to track our riders' every move ,that's a privacy nightmare. Instead, we put a tiny, smart program directly inside the app using **Edge Computing**.

- **How it helps:** The app checks the sensors, the cell towers, and the Wi-Fi locally on the phone. It just sends a tiny, secure message to our servers saying either _"Yes, they are really in the storm"_ or _"No, this looks fake."_
    
- **Offline Mode:** If the internet goes down during a heavy storm, the app remembers that the rider was there. Once the internet comes back, it sends the _"Yes"_ signal and they still get paid.
    

## Part 2: The News Reader 

Not all disruptions are weather-related. What if there is a sudden transport strike or a civic riot? Weather apps won't show that.

- **How it helps:** We built an AI pipeline that constantly reads live news articles. If it reads that a "Transport Strike" has started in "Bangalore" today, it automatically turns that news into a verified event in our database and triggers payouts for the affected riders.
    

---

## 5. Tech Stack

- **The App:** Flutter (UI) and TensorFlow Lite (Edge AI for fraud checks).
    
- **The Backend:** Node.js and PostgreSQL (User data & wallets).
    
- **The AI Brain (News Pipeline):** Python, Llama-3 (Reasoning), and Neo4j (Graph Database for tracking events).
    
- **Connections:** Razorpay/NPCI (Instant UPI transfers) and Account Aggregator (Secure income verification).
    

---

## 6. Persona / Situation

## The Vritti Impact: Rahul’s Story

**1. Meet Rahul (The Rider)**

- Rahul is a full-time Swiggy partner in Chennai making about **₹6,000 a week**.
    
- He supports his family and has a strict bike EMI. For him, a rainy day isn't just an inconvenience; it means missing a loan payment.
    

**2. The Weekly SIP (Saturday Morning)**

- Vritti works automatically in the background. Based on his income and Chennai's weather risks, his base premium is set.
    
- Because he has been a reliable, honest worker for two months, he gets a **10% loyalty discount**.
    
- He pays exactly **₹270 a week** -> less than a tank of petrol -> deducted automatically from his wallet.
    

**3. The Crisis (Tuesday, 2:00 PM)**

- A severe cyclone hits the coast. The IMD issues a **Red Alert**, and Swiggy suspends all deliveries for safety.
    
- In the past, Rahul would have huddled under a bridge, stressed about his lost income. Today, he just drives home safely.
    

**4. The Invisible Shield (Behind the Scenes)**

- **The Scammers:** A syndicate in Mumbai uses fake GPS apps to pretend they are in the Chennai storm to steal payouts. Vritti’s AI blocks them instantly because their phones don't feel the storm's barometric pressure or physical vibrations.
    
- **The Real Deal:** Rahul’s app silently pings the local **Chennai Cell Towers** and **Wi-Fi networks** to confirm he is actually in the disaster zone, even while he rests safely indoors.
    

**5. The Instant Relief (Tuesday, 4:00 PM)**

- The storm clears. Vritti’s Cloud Brain verifies the city was officially shut down.
    
- Using the daily city average (**₹500**) and a Red Alert multiplier (**1.5x**), the system automatically triggers a **₹750 payout**.
    
- The money hits Rahul's UPI account instantly. He lost hours on the road, but he didn't lose his livelihood, and the platform wasn't scammed.
