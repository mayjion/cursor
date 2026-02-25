Component({
  properties: {
    device: Object
  },

  data: {
    switchCapabilities: [],
    hasSchedule: false,
    taskList: []
  },

  lifetimes: {
    attached() {
      this.init()
    }
  },

  observers: {
    'device': function () {
      this.init()
    }
  },

  methods: {

    init() {
      const dev = this.data.device
      if (!dev || !dev.capabilities) return

      const switchCaps = dev.capabilities
        .filter(c => c.ui === 'switch')

      const hasSchedule = dev.capabilities.some(
        c => c.ui === 'schedule'
      )

      this.setData({
        switchCapabilities: switchCaps,
        hasSchedule
      })

      this.parseSchedule(dev.state?.schedule)
    },

    /* ===== 解析 schedule 仅展示 ===== */
    parseSchedule(schedule) {

      if (!schedule) {
        this.setData({ taskList: [] })
        return
      }

      let list = []

      /* 周期 */
      schedule.periods?.forEach(p => {

        const startH = Math.floor(p.start_min / 60)
        const startM = p.start_min % 60
        const endH = Math.floor(p.end_min / 60)
        const endM = p.end_min % 60

        list.push({
          desc:
            this.parseWeek(p.week_mask) +
            ` ${this.pad(startH)}:${this.pad(startM)}-` +
            `${this.pad(endH)}:${this.pad(endM)} ` +
            (p.state ? '开' : '关')
        })
      })

      /* 单次 */
      schedule.one_shot?.forEach(o => {
        const date = new Date(o.timestamp * 1000)
        list.push({
          desc:
            `${date.getMonth()+1}/${date.getDate()} ` +
            `${this.pad(date.getHours())}:${this.pad(date.getMinutes())} ` +
            (o.state ? '开' : '关')
        })
      })

      this.setData({ taskList: list })
    },

    parseWeek(mask) {
      const map = ['一','二','三','四','五','六','日']
      let str = ''
      const weekList = [
        { value: 1 },
        { value: 2 },
        { value: 4 },
        { value: 8 },
        { value: 16 },
        { value: 32 },
        { value: 64 }
      ]
      weekList.forEach((w,i)=>{
        if(mask & w.value) str+=map[i]
      })
      return str
    },

    pad(n){
      return n<10?'0'+n:n
    },

    /* ===== 跳转页面 ===== */
    goSchedulePage(){

      const dev = this.data.device

      wx.navigateTo({
        url: `/pages/schedule/index?productId=${dev.productId}&deviceName=${dev.deviceName}`
      })
    }

  }
})
